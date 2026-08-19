# Local Backend Setup for /pm:setup

Load this only when the user selects the local backend. Local needs no additional
interview or external provisioning.

## Backend Interview

No backend-specific questions are required.

## Generate .pm/config.yml

Use these values in the backend-specific placeholder in the main skill's shared
config:

```yaml
backend: local

local:
  items_dir: .pm/items
```

And create the `.pm/items/` directory.

## Provisioning

There is no external service to provision. Confirm the items directory exists.

## Summary lines

Record `Local items directory: {resolved items_dir}`.
