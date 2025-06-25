# CDP Forge Helm Chart

Questo pacchetto Helm deploya un cluster Kafka completo, un cluster OpenSearch e un cluster MySQL master-replica per CDP Forge utilizzando Strimzi Kafka Operator, OpenSearch Helm Chart e MySQL Bitnami Chart.

## Componenti

- **Strimzi Kafka Operator**: Operatore per gestire cluster Kafka su Kubernetes
- **Kafka Cluster**: Cluster Kafka con 3 repliche (High Availability)
- **OpenSearch Cluster**: Cluster OpenSearch con 6 nodi (3 master + 3 data)
- **OpenSearch Dashboards**: Interfaccia web per gestire OpenSearch
- **MySQL Cluster**: Cluster MySQL master-replica con automatic failover

## Prerequisiti

- Kubernetes 1.19+
- Helm 3.0+
- Storage class per persistent volumes

## Installazione

1. Aggiungi i repository necessari:
```bash
helm repo add strimzi https://strimzi.io/charts/
helm repo add opensearch https://opensearch-project.github.io/helm-charts/
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

2. Installa il chart:
```bash
helm install cdp-forge . -n cdpforge
```

## Configurazione

### Valori principali

| Parametro | Descrizione | Default |
|-----------|-------------|---------|
| `strimzi.enabled` | Abilita Strimzi Kafka Operator | `true` |
| `kafka.enabled` | Abilita il cluster Kafka | `true` |
| `kafka.replicas` | Numero di repliche Kafka | `3` |
| `kafka.storage.size` | Dimensione storage per Kafka | `10Gi` |
| `zookeeper.replicas` | Numero di repliche Zookeeper | `3` |
| `zookeeper.storage.size` | Dimensione storage per Zookeeper | `5Gi` |
| `opensearch.enabled` | Abilita il cluster OpenSearch | `true` |
| `opensearch.master.replicas` | Numero di repliche Master | `3` |
| `opensearch.data.replicas` | Numero di repliche Data | `3` |
| `opensearch.persistence.size` | Dimensione storage per OpenSearch | `20Gi` |
| `mysql.enabled` | Abilita il cluster MySQL | `true` |
| `mysql.secondary.replicaCount` | Numero di repliche MySQL | `2` |
| `mysql.persistence.size` | Dimensione storage per MySQL | `10Gi` |

### Listeners Kafka

Il cluster Kafka espone tre listener:
- **plain**: Porta 9092, senza TLS, accesso interno
- **tls**: Porta 9093, con TLS, accesso interno
- **external**: Porta 9094, senza TLS, accesso esterno via NodePort

### High Availability

Il cluster Kafka è configurato per High Availability:
- **3 repliche Kafka**: Protezione da fallimenti di singoli broker
- **Replication factor**: 3 per tutti i topic di sistema
- **Min ISR**: 2 per garantire disponibilità

### OpenSearch Security

L'operatore OpenSearch gestisce automaticamente:
- **Generazione password casuali** per tutti gli utenti
- **Creazione Kubernetes Secrets** con le credenziali
- **Configurazione TLS** per HTTP e transport
- **Setup autenticazione e autorizzazione**
- **Deploy OpenSearch Dashboards**

#### Password OpenSearch

Le password vengono generate automaticamente dall'operatore e salvate in Secret. Per recuperarle:

```bash
# Lista tutti i Secret di OpenSearch
kubectl get secrets | grep opensearch

# Recupera password admin (il nome del Secret può variare)
kubectl get secret <opensearch-secret-name> -o jsonpath='{.data.admin}' | base64 -d

# Oppure usa il comando fornito dall'operatore
kubectl get secret <opensearch-secret-name> -o jsonpath='{.data.admin}' | base64 -d
```

### MySQL Master-Replica con Automatic Failover

Il cluster MySQL è configurato con:
- **1 Master Node**: Gestisce scritture e transazioni
- **2 Replica Nodes**: Gestiscono letture e backup
- **Automatic Failover**: Promozione automatica di una replica a master
- **Backup automatici**: Backup giornalieri con retention di 7 giorni
- **Monitoring**: Metriche Prometheus integrate

#### Password MySQL

Le password vengono generate automaticamente e salvate in Secret:

```bash
# Recupera password root
kubectl get secret cdp-forge-mysql -o jsonpath='{.data.mysql-root-password}' | base64 -d

# Recupera password utente
kubectl get secret cdp-forge-mysql -o jsonpath='{.data.mysql-password}' | base64 -d
```

#### Connessione MySQL

```bash
# Connessione al master (scritture)
mysql -h cdp-forge-mysql-primary -u root -p

# Connessione alle repliche (letture)
mysql -h cdp-forge-mysql-secondary -u root -p

# Connessione utente applicazione
mysql -h cdp-forge-mysql-primary -u cdp_forge_user -p cdp_forge
```

### Configurazione avanzata

Modifica il file `values.yaml` per personalizzare:
- Risorse CPU e memoria
- Configurazioni Kafka, OpenSearch e MySQL
- Storage class
- Versioni delle immagini

## Utilizzo

### Connessione al cluster Kafka

```bash
# Bootstrap servers
cdp-forge-kafka-kafka-bootstrap:9092  # Plain
cdp-forge-kafka-kafka-bootstrap:9093  # TLS
```

### Connessione a OpenSearch

```bash
# Recupera la password admin dal Secret generato dall'operatore
ADMIN_PASSWORD=$(kubectl get secret <opensearch-secret-name> -o jsonpath='{.data.admin}' | base64 -d)

# OpenSearch REST API
curl -k -u admin:$ADMIN_PASSWORD https://cdp-forge-opensearch:9200

# OpenSearch Dashboards
# Accessibile tramite il service creato dall'operatore
```

### Connessione a MySQL

```bash
# Recupera password
MYSQL_PASSWORD=$(kubectl get secret cdp-forge-mysql -o jsonpath='{.data.mysql-password}' | base64 -d)

# Connessione al master
mysql -h cdp-forge-mysql-primary -u cdp_forge_user -p$MYSQL_PASSWORD cdp_forge

# Connessione alle repliche
mysql -h cdp-forge-mysql-secondary -u cdp_forge_user -p$MYSQL_PASSWORD cdp_forge
```

### Creazione di un topic Kafka

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

### Creazione di un indice OpenSearch

```bash
# Recupera la password admin
ADMIN_PASSWORD=$(kubectl get secret <opensearch-secret-name> -o jsonpath='{.data.admin}' | base64 -d)

# Crea un indice
curl -k -u admin:$ADMIN_PASSWORD -X PUT "https://cdp-forge-opensearch:9200/my-index" \
  -H "Content-Type: application/json" \
  -d '{
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 2
    }
  }'

# Inserisci un documento
curl -k -u admin:$ADMIN_PASSWORD -X POST "https://cdp-forge-opensearch:9200/my-index/_doc" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Document",
    "content": "This is a test document",
    "timestamp": "2024-01-01T00:00:00Z"
  }'
```

### Creazione di un utente Kafka

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

## Monitoraggio

I cluster includono:
- Metriche Prometheus per Kafka, OpenSearch e MySQL
- Health checks e probe di readiness/liveness
- Logging strutturato
- OpenSearch Dashboards per visualizzazione
- MySQL monitoring con ServiceMonitor

## Troubleshooting

### Verifica dello stato del cluster Kafka

```bash
kubectl get kafka
kubectl get kafka -o yaml
kubectl get pods -l strimzi.io/cluster=cdp-forge-kafka
```

### Verifica dello stato del cluster OpenSearch

```bash
kubectl get pods -l app=opensearch
kubectl logs -l app=opensearch

# Verifica connessione (usa password dal Secret dell'operatore)
ADMIN_PASSWORD=$(kubectl get secret <opensearch-secret-name> -o jsonpath='{.data.admin}' | base64 -d)
curl -k -u admin:$ADMIN_PASSWORD https://cdp-forge-opensearch:9200/_cluster/health
```

### Verifica dello stato del cluster MySQL

```bash
# Verifica pod MySQL
kubectl get pods -l app.kubernetes.io/name=mysql

# Verifica replicazione
kubectl exec -it cdp-forge-mysql-primary-0 -- mysql -u root -p -e "SHOW SLAVE HOSTS;"

# Verifica stato master/replica
kubectl exec -it cdp-forge-mysql-primary-0 -- mysql -u root -p -e "SHOW MASTER STATUS;"
kubectl exec -it cdp-forge-mysql-secondary-0 -- mysql -u root -p -e "SHOW SLAVE STATUS\G"
```

### Logs

```bash
# Kafka
kubectl logs -l strimzi.io/cluster=cdp-forge-kafka
kubectl logs -l strimzi.io/cluster=cdp-forge-zookeeper

# OpenSearch
kubectl logs -l app=opensearch
kubectl logs -l app=opensearch-dashboards

# MySQL
kubectl logs -l app.kubernetes.io/name=mysql
```

## Disinstallazione

```bash
helm uninstall cdp-forge
```

**Nota**: I persistent volumes e i Secret con le password non vengono eliminati automaticamente per preservare i dati e le credenziali. 