# Neo4j Enterprise Analytics Cluster Lab

Lab ini menyiapkan Neo4j Enterprise cluster di satu host Docker Compose untuk
mencoba pemisahan transactional workload dan analytics workload.

Topologi default:

- 3 transactional node: `tx1`, `tx2`, `tx3`
- 2 analytics node: `analytics1`, `analytics2`
- Database `neo4j`: `3 PRIMARIES 2 SECONDARIES`
- Database `system` pada analytics node dipaksa `SECONDARY`
- Graph Data Science aktif hanya di analytics node

## Struktur Project

```text
.
├── docker-compose.yml          # Stack Neo4j cluster
├── neo4j.conf                  # Shared cluster config
├── bootstrap/                  # Script bootstrap topology cluster
├── conf/                       # Bind mount config per node
├── import/                     # Folder import per node
├── licenses/                   # Optional GDS Enterprise license
└── plugins/                    # Runtime plugin directory per analytics node
```

Folder `data/`, `logs/`, dan file plugin `.jar` adalah artefak runtime dan tidak
di-commit ke Git. Neo4j Docker image akan memasang plugin GDS lewat
`NEO4J_PLUGINS` saat analytics node dijalankan.

## Prasyarat

- Docker dan Docker Compose plugin
- Neo4j Enterprise image dapat ditarik dari registry
- Resource host cukup untuk 5 container Neo4j

## Setup

Salin contoh environment:

```bash
cp .env.example .env
```

Sesuaikan nilai penting di `.env`:

- `NEO4J_PASSWORD`: password user `neo4j`
- `ADVERTISED_HOST`: `localhost` untuk mesin lokal, atau IP/DNS host Docker
- `USER_ID` dan `GROUP_ID`: UID/GID user host agar bind mount bisa ditulis
- Port `TX*` dan `ANALYTICS*` jika ada bentrok port

Jika belum tahu UID/GID host:

```bash
id -u
id -g
```

## Jalankan Cluster

```bash
docker compose up -d
docker compose logs -f cluster-init
```

Jika `cluster-init` selesai dengan pesan berikut, cluster sudah siap:

```text
Analytics cluster bootstrap finished.
```

## Endpoint

| Role | Browser HTTP | Direct Bolt |
| --- | --- | --- |
| Router / writer awal | `http://localhost:17474` | `neo4j://localhost:17687` |
| Transactional 2 | `http://localhost:17475` | `bolt://localhost:17688` |
| Transactional 3 | `http://localhost:17476` | `bolt://localhost:17689` |
| Analytics 1 | `http://localhost:17477` | `bolt://localhost:17690` |
| Analytics 2 | `http://localhost:17478` | `bolt://localhost:17691` |

Credential default:

- Username: `neo4j`
- Password: nilai `NEO4J_PASSWORD` di `.env`

## Verifikasi Cluster

Masuk ke `tx1` atau Neo4j Browser, lalu jalankan:

```cypher
SHOW SERVERS;
SHOW DATABASE neo4j;
```

Server `analytics1` dan `analytics2` seharusnya `Enabled`, dan database `neo4j`
memakai `3 PRIMARIES 2 SECONDARIES`.

## Menggunakan Analytics Node

Untuk query GDS, sambungkan client langsung ke analytics node dengan protokol
`bolt://`, misalnya:

```bash
source .env
cypher-shell -a bolt://localhost:17690 -u neo4j -p "${NEO4J_PASSWORD}"
```

Workload analytics sebaiknya dijalankan di server `SECONDARY`.

## GDS Enterprise Opsional

Secara default, compose menjalankan plugin GDS di mode Community pada analytics
node. Jika Anda punya lisensi GDS Enterprise:

1. Letakkan file lisensi di `./licenses/gds`
2. Ubah `GDS_LICENSE_FILE=/licenses/gds` di `.env`
3. Restart analytics node:

```bash
docker compose up -d --force-recreate analytics1 analytics2
```

## Reset Lab

Matikan container tanpa menghapus data:

```bash
docker compose down
```

Hapus state database dan log lokal:

```bash
docker compose down
rm -rf data logs plugins/analytics1/*.jar plugins/analytics2/*.jar
```

## Catatan

- Tag image default dipin ke `neo4j:2026.02.3-enterprise`.
- Jika host bukan mesin lokal, ubah `ADVERTISED_HOST` di `.env` ke DNS/IP host Docker.
- Untuk workload analytics Cypher berat non-GDS, Anda bisa menambahkan routing
  policy berbasis tag `analytics` karena kedua analytics node sudah diberi
  `initial.server.tags=analytics`.
