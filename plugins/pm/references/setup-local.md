# Local Backend Setup for /pm:setup

This is the local-backend setup detail for `/pm:setup`, split out of the main
`SKILL.md` for progressive disclosure — only load this when the user picks the
local markdown backend. It covers the Phase 3 config generation: the
local-specific fields to add to `.pm/config.yml`, and creating the
`.pm/items/` directory. There is no Batch 1.5-style interview or Phase 6-style
provisioning for this backend — local has no external service to configure.

## Generate .pm/config.yml

If the backend is `local`, omit the `github:` section entirely and add:

```yaml
# Local backend settings
local:
  items_dir: .pm/items
```

And create the `.pm/items/` directory.
