# MyServeCoach — Development Workflow Guide

## 🚀 Overview

This guide outlines the recommended development workflow for building the **MyServeCoach** iOS application using:

* **Xcode** (SwiftUI, SwiftData, AVFoundation, Vision)
* **GitHub** (version control)
* **Linear** (project management)
* **Claude Code** (AI coding assistant)
* **macOS** (required for iOS builds)

It establishes consistency, speed, and maintainability across the project.

---

# 1. 🧰 Development Environment

## Required Tools

| Tool                                       | Purpose                                       |
| ------------------------------------------ | --------------------------------------------- |
| **Xcode (latest stable)**                  | Building, running, and debugging iOS apps     |
| **Git + GitHub**                           | Version control + PR workflow                 |
| **Linear**                                 | Issue tracking + project management           |
| **Claude Code**                            | Coding assistance, refactoring, documentation |
| **macOS (M2 or above recommended)**        | Required for iOS toolchain                    |
| **Optional:** Raycast, SwiftLint, Fastlane | Productivity, formatting, and CI/CD           |

---

# 2. 🧱 Project Structure

Recommended repo structure:

```
MyServeCoach/
    App/
        Views/
        ViewModels/
        Models/
            SwiftData/
        Services/
            Video/
            Pose/
            Coaching/
        Resources/
    Tests/
    README.md
    .gitignore
    LICENSE
```

---

# 3. 🛠️ Local Development Workflow

## Step-by-step daily workflow

### **1. Start your day**

* Pull from `develop`
* Open Linear → pick today’s issue
* Open Xcode
* Open Claude Code (browser or desktop app)

---

### **2. Create a feature branch**

Branch name patterns:

```
feature/video-processing
feature/pose-estimation
bugfix/swiftdata-crash
chore/refactor-viewmodels
```

Command:

```
git checkout -b feature/<name>
```

---

### **3. Build the feature**

* Implement logic/UI in Xcode
* Use Claude Code for:

  * generating SwiftUI screens
  * AVFoundation code
  * debugging compiler errors
  * writing tests
  * refactoring

**Tip:** Keep Xcode and Claude side-by-side.

---

### **4. Test the feature**

* Use the iOS Simulator
* Test on a real device for camera features
* Validate SwiftData persistence
* Print Vision results to console early for debugging

---

### **5. Commit often**

* Make frequent, small commits
* Write descriptive commit messages
* Never commit derived or generated files

Example:

```
git add .
git commit -m "Add Serve model with SwiftData + basic fields"
```

---

### **6. Push & Create PR**

Push:

```
git push --set-upstream origin feature/<name>
```

Create PR → Assign yourself.

---

### **7. Use Claude for PR review**

Paste the diff into Claude with a prompt such as:

> “Review this PR for structure, Swift best practices, safety, and optimization.”

Incorporate improvements, then re-push.

---

### **8. Merge into `develop`**

Once approved:

* Squash & merge
* Linear issue should auto-update if integrated correctly

---

### **9. End of day**

* Close the Linear issue(s) you completed
* Move the next issue into "In Progress"
* Update architecture docs if needed

---

# 4. 🧪 Testing Workflow

Use a combination of:

### **Unit Tests**

* Pose pipeline math
* Video processing abstractions
* Coaching logic (mocked)

### **Snapshot Tests**

* SwiftUI views (using ViewInspector)

### **Manual Tests**

* Recording serve videos
* Video playback
* Pose detection accuracy
* Edge cases (low light, shaky camera)

Claude can generate most test scaffolding quickly.

---

# 5. 🧩 Branching Strategy

### **Branches**

* `main` → production-ready releases
* `develop` → active development
* `feature/*` → individual features
* `hotfix/*` → urgent fixes

### **Releases**

Tag stable builds:

```
git tag -a v0.1.0 -m "MVP"
git push origin v0.1.0
```

---

# 6. 🤖 Best Practices for Using Claude Code

### Ideal uses:

* Turning Linear issues into working code
* Generating SwiftUI components
* Writing AVFoundation pipelines
* Constructing Vision pose-analysis functions
* Refactoring and optimizing Swift
* Producing documentation and architecture diagrams
* Drafting PR descriptions
* Helping debug compiler errors

### Avoid using Claude for:

* Code signing or provisioning issues
* Simulator/device debugging
* Real-time UI previews
* Solving Xcode-specific configuration errors

These must be handled within Xcode or manually.

---

# 7. 🎯 Weekly Workflow Summary

### **Monday**

* Groom Linear issues
* Define weekly scope
* Architectural discussions

### **Tuesday–Thursday**

* Implement features
* PR reviews
* Refactors
* Testing

### **Friday**

* Merge week’s work
* Smoke test build
* Tag optional weekly release (e.g., `v0.0.5`)

---

# 8. 🔐 Code Quality Standards

* Use MVVM for structure
* Keep SwiftUI views thin
* Move logic into services
