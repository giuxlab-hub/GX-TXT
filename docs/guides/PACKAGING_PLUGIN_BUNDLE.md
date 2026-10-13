# Packaging a GX-TXT plugin bundle

Use a bundle only when one feature must be distributed as **multiple independent
GX-TXT plugins**. A typical case is one analysis module plus several
`kind=parameter_law` mathematical models.

First package every member exactly as if it were going to be installed alone:

```text
packages/my.module/plugin-package.ini
packages/my.module/module.ini
packages/law.linear/plugin-package.ini
packages/law.linear/model.ini
```

Then add one `plugin-bundle.ini` at the bundle root:

```ini
[bundle]
api_version=1
id=my.feature
name=My Feature
version=1.0.0
framework_min=0.9.3.2

[packages]
paths=packages/my.module;packages/law.linear
```

Create one ZIP containing that root. The user installs the ZIP with the normal
**Install plugin...** action. GX-TXT validates and stages all members before the
first live commit; if any member fails, all members are rolled back.

Do not add install scripts, destination paths or shell commands. The bundle is a
declarative package set only.
