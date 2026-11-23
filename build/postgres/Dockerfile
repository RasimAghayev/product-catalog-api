# The database image of the compose stack of product-catalog-api.
#
# The service builds from this file instead of pointing at a registry image
# (R91). The base image is pinned by digest.

FROM postgres:19-alpine@sha256:cac45fb483caee3668946088a1c0532db89d5285c28dbfeac889b4068296e06f

# The data directory is a bind mount from var/postgres, so the permissions of
# the mount point are set on the host side.
WORKDIR /var/lib/postgresql/data
