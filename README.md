# Neo4j Enterprise Analytics Cluster Lab

This lab runs a Neo4j Enterprise cluster on a single Docker Compose host for
experimenting with separated transactional and analytics workloads.

Default topology:

- 3 transactional nodes: `tx1`, `tx2`, `tx3`
- 2 analytics nodes: `analytics1`, `analytics2`
- `neo4j` database: `3 PRIMARIES 2 SECONDARIES`
- `system` database on analytics nodes is forced to `SECONDARY`
- Graph Data Science is enabled only on the analytics nodes

## Project Structure

```text
.
├── docker-compose.yml          # Neo4j cluster stack
├── neo4j.conf                  # Shared cluster config
├── bootstrap/                  # Cluster topology bootstrap script
├── conf/                       # Per-node config bind mounts
├── import/                     # Per-node import folders
├── licenses/                   # Optional GDS Enterprise license
└── plugins/                    # Runtime plugin directory for analytics nodes
```

The `data/`, `logs/`, and plugin `.jar` files are runtime artifacts and are not
committed to Git. The Neo4j Docker image installs the GDS plugin through
`NEO4J_PLUGINS` when the analytics nodes start.

## Requirements

- Docker and the Docker Compose plugin
- Access to pull the Neo4j Enterprise image
- Enough host resources to run 5 Neo4j containers

## Setup

Copy the example environment file:

```bash
cp .env.example .env
```

Adjust the important values in `.env`:

- `NEO4J_PASSWORD`: password for the `neo4j` user
- `ADVERTISED_HOST`: `localhost` for a local machine, or the Docker host IP/DNS
- `USER_ID` and `GROUP_ID`: host UID/GID so bind mounts are writable
- `TX*` and `ANALYTICS*` ports if there are local port conflicts

If you do not know the host UID/GID:

```bash
id -u
id -g
```

## Running the Cluster

```bash
docker compose up -d
docker compose logs -f cluster-init
```

The cluster is ready when `cluster-init` finishes with:

```text
Analytics cluster bootstrap finished.
```

## Endpoints

| Role | Browser HTTP | Direct Bolt |
| --- | --- | --- |
| Initial router / writer | `http://localhost:17474` | `neo4j://localhost:17687` |
| Transactional 2 | `http://localhost:17475` | `bolt://localhost:17688` |
| Transactional 3 | `http://localhost:17476` | `bolt://localhost:17689` |
| Analytics 1 | `http://localhost:17477` | `bolt://localhost:17690` |
| Analytics 2 | `http://localhost:17478` | `bolt://localhost:17691` |

Default credentials:

- Username: `neo4j`
- Password: the `NEO4J_PASSWORD` value in `.env`

## Verifying the Cluster

Connect to `tx1` or Neo4j Browser, then run:

```cypher
SHOW SERVERS;
SHOW DATABASE neo4j;
```

The `analytics1` and `analytics2` servers should be `Enabled`, and the `neo4j`
database should use `3 PRIMARIES 2 SECONDARIES`.

## Using the Analytics Nodes

For GDS queries, connect directly to an analytics node with the `bolt://`
protocol, for example:

```bash
source .env
cypher-shell -a bolt://localhost:17690 -u neo4j -p "${NEO4J_PASSWORD}"
```

Analytics workloads should run on `SECONDARY` servers.

## Optional GDS Enterprise License

By default, this compose stack runs the GDS plugin in Community mode on the
analytics nodes. If you have a GDS Enterprise license:

1. Place the license file at `./licenses/gds`
2. Set `GDS_LICENSE_FILE=/licenses/gds` in `.env`
3. Recreate the analytics nodes:

```bash
docker compose up -d --force-recreate analytics1 analytics2
```

## Resetting the Lab

Stop the containers without deleting data:

```bash
docker compose down
```

Delete local database state and logs:

```bash
docker compose down
rm -rf data logs plugins/analytics1/*.jar plugins/analytics2/*.jar
```

## Notes

- The default image tag is pinned to `neo4j:2026.02.3-enterprise`.
- If the host is not your local machine, set `ADVERTISED_HOST` in `.env` to the Docker host DNS/IP.
- For heavy non-GDS analytics Cypher workloads, you can add a routing policy
  based on the `analytics` tag because both analytics nodes use
  `initial.server.tags=analytics`.
