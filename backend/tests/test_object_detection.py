import numpy as np
import pytest

from app.services.object_detection import (
    ObjectDetectionModel,
    map_yolo_results_to_detections,
    select_largest_person_box,
)

WIDTH = 100
HEIGHT = 200


class _StubBoxes:
    def __init__(self, cls, conf, xyxy):
        self.cls = np.array(cls)
        self.conf = np.array(conf)
        self.xyxy = np.array(xyxy)


def test_tennis_racket_maps_to_racket_label():
    boxes = _StubBoxes(cls=[38], conf=[0.9], xyxy=[[10.0, 20.0, 30.0, 40.0]])

    result = map_yolo_results_to_detections(boxes, WIDTH, HEIGHT, confidence_threshold=0.25)

    assert len(result) == 1
    assert result[0].label == "racket"
    assert result[0].confidence == pytest.approx(0.9)


def test_sports_ball_maps_to_ball_label():
    boxes = _StubBoxes(cls=[32], conf=[0.8], xyxy=[[10.0, 20.0, 30.0, 40.0]])

    result = map_yolo_results_to_detections(boxes, WIDTH, HEIGHT, confidence_threshold=0.25)

    assert len(result) == 1
    assert result[0].label == "ball"
    assert result[0].confidence == pytest.approx(0.8)


def test_bbox_normalized_and_y_flipped_to_vision_convention():
    # A box near the top of the image in OpenCV pixel space (small y) must map to
    # y values close to 1.0 in the Vision-derived convention (origin bottom-left,
    # y-up) — not close to 0.
    boxes = _StubBoxes(cls=[38], conf=[0.9], xyxy=[[0.0, 0.0, 50.0, 20.0]])

    result = map_yolo_results_to_detections(boxes, WIDTH, HEIGHT, confidence_threshold=0.25)

    bbox = result[0].bbox
    assert bbox.x_min == pytest.approx(0.0)
    assert bbox.x_max == pytest.approx(0.5)
    assert bbox.y_min == pytest.approx(0.9)
    assert bbox.y_max == pytest.approx(1.0)


def test_y_min_less_than_y_max_after_flip():
    boxes = _StubBoxes(cls=[32], conf=[0.9], xyxy=[[10.0, 50.0, 30.0, 150.0]])

    result = map_yolo_results_to_detections(boxes, WIDTH, HEIGHT, confidence_threshold=0.25)

    bbox = result[0].bbox
    assert bbox.y_min < bbox.y_max


def test_non_racket_ball_classes_dropped():
    boxes = _StubBoxes(
        cls=[0, 38],  # person, racket
        conf=[0.95, 0.9],
        xyxy=[[0.0, 0.0, 10.0, 10.0], [10.0, 20.0, 30.0, 40.0]],
    )

    result = map_yolo_results_to_detections(boxes, WIDTH, HEIGHT, confidence_threshold=0.25)

    assert len(result) == 1
    assert result[0].label == "racket"


def test_below_threshold_detection_dropped():
    boxes = _StubBoxes(cls=[38], conf=[0.1], xyxy=[[10.0, 20.0, 30.0, 40.0]])

    result = map_yolo_results_to_detections(boxes, WIDTH, HEIGHT, confidence_threshold=0.25)

    assert result == []


def test_empty_boxes_produces_empty_list():
    boxes = _StubBoxes(cls=[], conf=[], xyxy=np.empty((0, 4)))

    result = map_yolo_results_to_detections(boxes, WIDTH, HEIGHT, confidence_threshold=0.25)

    assert result == []


# --- select_largest_person_box (fused pose pipeline's person-bbox source, Group 0) ---


def test_select_largest_person_box_picks_largest_area_not_highest_confidence():
    # A small, high-confidence crowd member at index 0; a larger, lower-confidence foreground
    # player at index 1 — area, not confidence, must decide the winner.
    boxes = _StubBoxes(
        cls=[0, 0],
        conf=[0.95, 0.5],
        xyxy=[[0.0, 0.0, 10.0, 10.0], [0.0, 0.0, 200.0, 300.0]],
    )

    result = select_largest_person_box(boxes)

    assert result == [0.0, 0.0, 200.0, 300.0]


def test_select_largest_person_box_returns_pixel_xyxy_unflipped_unnormalized():
    boxes = _StubBoxes(cls=[0], conf=[0.9], xyxy=[[10.0, 20.0, 30.0, 40.0]])

    result = select_largest_person_box(boxes)

    # No normalization (values stay in pixel space, not [0,1]) and no y-flip (y_min < y_max in
    # the original OpenCV top-left-origin convention, unlike map_yolo_results_to_detections'
    # Vision-convention output).
    assert result == [10.0, 20.0, 30.0, 40.0]


def test_select_largest_person_box_ignores_non_person_classes():
    boxes = _StubBoxes(cls=[38], conf=[0.9], xyxy=[[10.0, 20.0, 30.0, 40.0]])  # racket only

    assert select_largest_person_box(boxes) is None


def test_select_largest_person_box_returns_none_when_no_person():
    boxes = _StubBoxes(cls=[], conf=[], xyxy=np.empty((0, 4)))

    assert select_largest_person_box(boxes) is None


# --- ObjectDetectionModel.infer_with_person (Group 0 fused pipeline's entry point) ---


class _StubYOLOResult:
    def __init__(self, boxes: _StubBoxes):
        self.boxes = boxes


class _StubYOLOModel:
    """Stands in for the ultralytics.YOLO instance ObjectDetectionModel lazily loads."""

    def __init__(self, boxes: _StubBoxes):
        self._boxes = boxes
        self.predict_call_count = 0

    def predict(self, image, device, conf, verbose):
        self.predict_call_count += 1
        return [_StubYOLOResult(self._boxes)]


def test_infer_with_person_returns_pixel_xyxy_unflipped_unnormalized_alongside_detections():
    boxes = _StubBoxes(
        cls=[0, 38],  # person, racket
        conf=[0.9, 0.9],
        xyxy=[[10.0, 20.0, 30.0, 40.0], [50.0, 60.0, 70.0, 80.0]],
    )
    model = ObjectDetectionModel()
    model._model = _StubYOLOModel(boxes)
    image = np.zeros((HEIGHT, WIDTH, 3), dtype=np.uint8)

    detections, person_box = model.infer_with_person(image)

    # Racket/ball detections still come back normalized + y-flipped, exactly as `infer` produces.
    assert len(detections) == 1
    assert detections[0].label == "racket"
    # Person box stays pixel xyxy, unflipped and unnormalized (rtmlib's own convention).
    assert person_box == [10.0, 20.0, 30.0, 40.0]


def test_infer_with_person_returns_none_when_no_person_clears_threshold():
    boxes = _StubBoxes(cls=[38], conf=[0.9], xyxy=[[50.0, 60.0, 70.0, 80.0]])  # racket only
    model = ObjectDetectionModel()
    model._model = _StubYOLOModel(boxes)
    image = np.zeros((HEIGHT, WIDTH, 3), dtype=np.uint8)

    _, person_box = model.infer_with_person(image)

    assert person_box is None
