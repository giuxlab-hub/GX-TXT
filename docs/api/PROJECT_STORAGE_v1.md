# Project and Session storage

The configured Session / Project root is the normal creation location. A new Project receives a stable ID independent of its display name and a directory `<root>/<project-id>/`. Its `project.ini` stores descriptive metadata; `Sessions/` contains new Sessions created for that Project. The user registry records the Project's storage path so renaming or changing the configured root does not move an existing Project.

The New Session dialog offers **Standalone Session** and every registered Project. Standalone Sessions are created directly under the configured root and associated with the persistent Default / Unassigned Project. Project Sessions are created under that Project's `Sessions/` directory and linked by Project and Experiment IDs in the Session manifest and membership registry. The Projects page also offers **New Session in Project...** for its selected Project.

Previously associated Sessions keep their existing paths. The framework does not relocate data when an Experiment is associated with or detached from a Project. Existing Projects without a stored path acquire a Project directory only when a new Session is created for them.

Dev083 Detach is reassignment to Default; all existing Session paths remain unchanged.
