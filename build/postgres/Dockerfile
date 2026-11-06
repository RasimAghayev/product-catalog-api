# The database image of the compose stack of product-catalog-api.
#
# The service builds from this file instead of pointing at a registry image
# (R91). The base image is pinned by digest.

FROM postgres:18-alpine@sha256:123b17998ccaf47e53b502e8c6a1e79afd8f579c6f3eec83c563da026f957395

# The data directory is a bind mount from var/postgres, so the permissions of
# the mount point are set on the host side.
WORKDIR /var/lib/postgresql/data
