import numpy as np
import pytest

from app.services.object_detection import map_yolo_results_to_detections

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
