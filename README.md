# CDP Forge Helm Chart

This Helm package deploys a complete Pulsar cluster, OpenSearch cluster, and MySQL master-replica cluster for CDP Forge using Strimzi Kafka Operator, official OpenSearch Helm Chart, and MySQL Bitnami Chart.

## Components

- **Pulsar Cluster**: Pulsar cluster with High Availability
- **OpenSearch Cluster**: OpenSearch cluster with 3 nodes (all roles: master, data, ingest)
- **OpenSearch Dashboards**: Web interface for managing OpenSearch
- **MySQL Cluster**: MySQL master-replica cluster with automatic failover

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Storage class for persistent volumes

## Installation

### Quick Installation

Use the provided installation script:

```bash
# Installation with default values
./install.sh

# Installation with custom values file
./install.sh -f custom-values.yaml

# Installation with custom namespace
./install.sh -n my-namespace -f custom-values.yaml
```

### Manual Installation

1. Add the required repositories:
```bash
helm repo add strimzi https://strimzi.io/charts/
helm repo add opensearch https://opensearch-project.github.io/helm-charts/
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

2. Install the chart:
```bash
helm install cdp-forge . -n cdpforge -f values.yaml
```

## Configuration

### Main Parameters

| Parameter | Description | Default |
| `opensearch.enabled` | Enable OpenSearch cluster | `true` |
| `opensearch.replicas` | Number of OpenSearch replicas | `3` |
| `opensearch.persistence.size` | Storage size for OpenSearch | `20Gi` |
| `opensearch-dashboards.enabled` | Enable OpenSearch Dashboards | `true` |
| `mysql.enabled` | Enable MySQL cluster | `true` |
| `mysql.secondary.replicaCount` | Number of MySQL replicas | `2` |
| `mysql.persistence.size` | Storage size for MySQL | `10Gi` |

### OpenSearch Security

The official OpenSearch chart manages:
- **Configured admin password**: `CdpForge@2024!` (meets OpenSearch 3.1.0+ security requirements)
- **TLS configuration** for HTTP and transport
- **Authentication and authorization setup**
- **Integrated OpenSearch Dashboards**

#### OpenSearch Passwords

The admin password is configured in the `values.yaml` file:
- **Username**: `admin`
- **Password**: `CdpForge@2024!`

To retrieve the password from an existing Secret:

```bash
# Retrieve admin password from Secret
kubectl get secret cdp-forge-opensearch-master -o jsonpath='{.data.admin-password}' | base64 -d
```

### MySQL Master-Replica with Automatic Failover

The MySQL cluster is configured with:
- **1 Master Node**: Handles writes and transactions
- **2 Replica Nodes**: Handle reads and backups
- **Automatic Failover**: Automatic promotion of a replica to master
- **Automatic backups**: Daily backups with 7-day retention
- **Monitoring**: Integrated Prometheus metrics (ServiceMonitor disabled by default)
- **Database Migrations**: Flyway-based schema versioning using [CDP Forge core-mysql repository](https://github.com/CDPForge/core-mysql.git)

#### MySQL Passwords

Passwords are configured in the `values.yaml` file:
- **Root Password**: `cdp-forge-root-2024`
- **User Password**: `cdp-forge-user-2024`
- **Replication Password**: `CdpForge@2024!`

To retrieve passwords from existing Secrets:

```bash
# Retrieve root password
kubectl get secret cdp-forge-mysql -o jsonpath='{.data.mysql-root-password}' | base64 -d

# Retrieve user password
kubectl get secret cdp-forge-mysql -o jsonpath='{.data.mysql-password}' | base64 -d

# Retrieve replication password
kubectl get secret cdp-forge-mysql -o jsonpath='{.data.mysql-replication-password}' | base64 -d
```

#### MySQL Connection

```bash
# Connect to master (writes)
mysql -h cdp-forge-mysql-primary -u root -p

# Connect to replicas (reads)
mysql -h cdp-forge-mysql-secondary -u root -p

# Connect application user
mysql -h cdp-forge-mysql-primary -u cdp_forge_user -p cdpforge
```

### Advanced Configuration

Modify the `values.yaml` file to customize:
- CPU and memory resources
- Kafka, OpenSearch, and MySQL configurations
- Storage class
- Image versions
- Passwords and credentials
- Flyway migration settings

#### Flyway Configuration

The MySQL initialization uses Flyway for database schema versioning:

```yaml
mysql:
  init:
    flyway:
      enabled: true
      repository: "https://github.com/CDPForge/core-mysql.git"
      version: "9.22.3"
```

Flyway automatically:
- Clones the core-mysql repository
- Downloads and installs Flyway CLI
- Executes all migration scripts in version order
- Creates application users with proper permissions
- Validates migration integrity

## Usage

### Connecting to Kafka Cluster

```bash
# Bootstrap servers
cdp-forge-kafka-kafka-bootstrap:9092  # Plain
cdp-forge-kafka-kafka-bootstrap:9093  # TLS
```

### Connecting to OpenSearch

```bash
# OpenSearch REST API
curl -k -u admin:CdpForge@2024! https://cdp-forge-opensearch-master:9200

# OpenSearch Dashboards
# Accessible via: cdp-forge-opensearch-dashboards:5601
```

### Connecting to MySQL

```bash
# Connect to master
mysql -h cdp-forge-mysql-primary -u cdp_forge_user -pcdp-forge-user-2024 cdpforge

# Connect to replicas
mysql -h cdp-forge-mysql-secondary -u cdp_forge_user -pcdp-forge-user-2024 cdpforge
```

### Database Migrations

The MySQL database uses Flyway for schema versioning. To add new migrations:

1. **Add migration scripts** to the [core-mysql repository](https://github.com/CDPForge/core-mysql.git):
   ```sql
   -- File: sql/V2__add_new_table.sql
   CREATE TABLE new_table (
     id INT PRIMARY KEY AUTO_INCREMENT,
     name VARCHAR(100) NOT NULL,
     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
   );
   ```

2. **Follow Flyway naming convention**:
   ```
   V<version>__<description>.sql
   ```

3. **Redeploy the chart** to apply migrations:
   ```bash
   helm upgrade cdp-forge . -f values.yaml
   ```

Flyway will automatically:
- Detect new migration scripts
- Execute them in version order
- Track migration history in `flyway_schema_history` table
- Prevent duplicate executions

### Creating a Kafka Topic

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: my-topic
  labels:
    strimzi.io/cluster: cdp-forge-kafka
spec:
  partitions: 3
  replicas: 3
  config:
    retention.ms: 7200000
    segment.bytes: 1073741824
```

### Creating an OpenSearch Index

```bash
# Create an index
curl -k -u admin:CdpForge@2024! -X PUT "https://cdp-forge-opensearch-master:9200/my-index" \
  -H "Content-Type: application/json" \
  -d '{
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 2
    }
  }'

# Insert a document
curl -k -u admin:CdpForge@2024! -X POST "https://cdp-forge-opensearch-master:9200/my-index/_doc" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Document",
    "content": "This is a test document",
    "timestamp": "2024-01-01T00:00:00Z"
  }'
```

### Creating a Kafka User

```yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: my-user
  labels:
    strimzi.io/cluster: cdp-forge-kafka
spec:
  authentication:
    type: scram-sha-512
  authorization:
    type: simple
    acls:
      - resource:
          type: topic
          name: my-topic
          patternType: literal
        operation: Read
        host: "*"
```

## Monitoring

The clusters include:
- Prometheus metrics for Kafka, OpenSearch, and MySQL
- Health checks and readiness/liveness probes
- Structured logging
- OpenSearch Dashboards for visualization
- MySQL monitoring with ServiceMonitor (disabled by default)

## Troubleshooting

### Checking Kafka Cluster Status

```bash
kubectl get kafka
kubectl get kafka -o yaml
kubectl get pods -l strimzi.io/cluster=cdp-forge-kafka
```

### Checking OpenSearch Cluster Status

```bash
kubectl get pods -l app.kubernetes.io/name=opensearch
kubectl logs -l app.kubernetes.io/name=opensearch

# Check connection
curl -k -u admin:CdpForge@2024! https://cdp-forge-opensearch-master:9200/_cluster/health
```

### Checking MySQL Cluster Status

```bash
# Check MySQL pods
kubectl get pods -l app.kubernetes.io/name=mysql

# Check replication
kubectl exec -it cdp-forge-mysql-primary-0 -- mysql -u root -p -e "SHOW SLAVE HOSTS;"

# Check master/replica status
kubectl exec -it cdp-forge-mysql-primary-0 -- mysql -u root -p -e "SHOW MASTER STATUS;"
kubectl exec -it cdp-forge-mysql-secondary-0 -- mysql -u root -p -e "SHOW SLAVE STATUS\G"

# Check Flyway migration status
kubectl exec -it cdp-forge-mysql-primary-0 -- mysql -u root -p cdpforge -e "SELECT * FROM flyway_schema_history ORDER BY installed_rank;"
```

### Logs

```bash
# Kafka
kubectl logs -l strimzi.io/cluster=cdp-forge-kafka
kubectl logs -l strimzi.io/cluster=cdp-forge-zookeeper

# OpenSearch
kubectl logs -l app.kubernetes.io/name=opensearch
kubectl logs -l app.kubernetes.io/name=opensearch-dashboards

# MySQL
kubectl logs -l app.kubernetes.io/name=mysql

# Flyway migration logs
kubectl logs -l app.kubernetes.io/component=mysql -c mysql-init

## Uninstallation

### Quick Uninstallation

Use the provided uninstallation script:

```bash
# Uninstallation with default namespace
./uninstall.sh

# Uninstallation with custom namespace
./uninstall.sh -n my-namespace
```

### Manual Uninstallation

```bash
helm uninstall cdp-forge -n cdpforge
```

**Note**: Persistent volumes and Secrets with passwords are not automatically deleted to preserve data and credentials.

## Security Notes

- **OpenSearch 3.1.0+**: Requires passwords that meet specific security criteria (minimum 8 characters, uppercase, lowercase, digits, and special characters)
- **MySQL Replication**: Uses separate replication password for security
- **TLS**: Enabled for OpenSearch HTTP and transport
- **ServiceMonitor**: Disabled by default for MySQL (requires Prometheus Operator) 