# Laboratorio Kubernetes con K3d (Mac)

## Objetivo

Levantar un cluster Kubernetes local utilizando K3d, desplegar una aplicación Nginx, escalarla, exponerla mediante Services y comprender el networking interno del cluster.

---

## Sesión 1 — K3d con Docker

### 1. Diagnóstico inicial

Se detectó que existían varios clusters K3d:

```bash
k3d cluster list
```

Resultado observado:

```
calicovet
lab-k8s
tp-k8s
curso-k8s
```

También se verificaron los contextos de kubectl:

```bash
kubectl config get-contexts
```

---

### 2. Problema de Kubeconfig

Al intentar utilizar el cluster `curso-k8s`, kubectl seguía apuntando a otro cluster (`calicovet`) o a un endpoint inválido.

Verificaciones realizadas:

```bash
kubectl config current-context
kubectl get nodes
```

Error observado:

```
The connection to the server 0.0.0.0:xxxxx was refused
```

Se identificó que el kubeconfig correcto estaba en:

```
~/.config/k3d/kubeconfig-curso-k8s.yaml
```

Prueba exitosa:

```bash
kubectl --kubeconfig=/Users/ariel.a.seba/.config/k3d/kubeconfig-curso-k8s.yaml get nodes
```

Resultado:

```
k3d-curso-k8s-server-0
k3d-curso-k8s-agent-0
k3d-curso-k8s-agent-1
```

---

### 3. Configuración del Kubeconfig

Se configuró la variable de entorno:

```bash
export KUBECONFIG=/Users/ariel.a.seba/.config/k3d/kubeconfig-curso-k8s.yaml
```

Verificación:

```bash
kubectl config current-context
# k3d-curso-k8s
```

---

### 4. Validación del cluster

```bash
kubectl get nodes
```

Resultado: 1 Control Plane + 2 Worker Nodes, todos en estado `Ready`.

---

### 5. Creación del Deployment Nginx

Archivo: `kubernetes-lab/nginx-deployment.yaml`

```bash
kubectl apply -f kubernetes-lab/nginx-deployment.yaml
kubectl get all
```

Resultado: Deployment nginx + ReplicaSet nginx + 3 Pods nginx.

---

### 6. Análisis de Pods

```bash
kubectl get pods -o wide
```

Los Pods fueron distribuidos entre los nodos del cluster:

```
k3d-curso-k8s-agent-0
k3d-curso-k8s-agent-1
k3d-curso-k8s-server-0
```

> **Concepto:** El Kubernetes Scheduler distribuye cargas entre los nodos disponibles.

---

### 7. Escalado del Deployment

```bash
kubectl scale deployment nginx --replicas=6
kubectl get pods -o wide
```

Resultado: 6 Pods ejecutándose, distribuidos 2 por nodo.

> **Concepto:** Kubernetes intenta distribuir las réplicas de manera equilibrada entre los nodos.

---

### 8. Creación de Service ClusterIP

Archivo: `kubernetes-lab/nginx-service.yaml`

```bash
kubectl apply -f kubernetes-lab/nginx-service.yaml
kubectl get svc
```

Resultado: `nginx-service   ClusterIP`

> **Concepto:** ClusterIP permite acceso interno dentro del cluster únicamente.

---

### 9. Validación de Endpoints

```bash
kubectl get endpoints nginx-service
```

Resultado: una entrada `10.42.x.x:80` por cada Pod.

> **Concepto:** El Service detecta automáticamente los Pods mediante Labels y Selectors.

---

### 10. Prueba de DNS interno

```bash
kubectl run test --rm -it --image=busybox -- sh
```

Dentro del Pod:

```sh
nslookup nginx-service
```

Resultado:

```
nginx-service.default.svc.cluster.local
10.43.131.153
```

> **Conceptos:** CoreDNS · Service Discovery · DNS interno de Kubernetes.

---

### 11. Creación de Service NodePort

Archivo: `kubernetes-lab/nginx-nodeport.yaml`

```bash
kubectl apply -f kubernetes-lab/nginx-nodeport.yaml
kubectl get svc
```

Resultado: `nginx-nodeport   NodePort   80:30080/TCP`

> **Concepto:** NodePort expone servicios a través de un puerto en cada nodo del cluster.

---

### 12. Diagnóstico de acceso externo

```bash
kubectl describe svc nginx-nodeport
docker ps | grep curso-k8s
```

**Problema detectado:** K3d no publicó el puerto NodePort hacia macOS. El cluster fue creado sin mapear puertos HTTP hacia el host. Solo el puerto `6443` (API server) estaba mapeado:

```
0.0.0.0:64679 -> 6443
```

> **Conclusión:** Para exponer NodePorts al host, el cluster debe crearse con el flag `--port`.

---

### 13. Validación final del Networking

```bash
kubectl run curlpod --rm -it --image=curlimages/curl -- sh
```

Dentro del Pod:

```sh
curl http://nginx-service
# Welcome to nginx!
```

Flujo validado:

```
curlpod → CoreDNS → Service → Endpoints → Pods nginx
```

---

### Conocimientos adquiridos (Sesión 1)

K3d · K3s · kubectl · Contextos · Kubeconfig · Deployments · ReplicaSets · Pods · Scheduler · Scaling · Services ClusterIP · Services NodePort · Endpoints · CoreDNS · DNS interno · Service Discovery · Networking entre Pods · Troubleshooting básico

---

## Sesión 2 — Migración a Podman

### Contexto

Al intentar hacer stop/start del cluster `curso-k8s`, K3d falló al reiniciarlo porque usaba Docker como runtime. Se decidió migrar a **Podman**.

### Por qué falló el restart

K3d usa la API de Docker para gestionar los contenedores del cluster. En Mac con Podman, la API Docker es emulada por la VM de Podman, expuesta a través de un **socket Unix**. El problema fue que `DOCKER_HOST` no estaba seteada, por lo que K3d buscó el socket en `/var/run/docker.sock` (la ruta de Docker nativo), que no existe.

```
Sin DOCKER_HOST →  K3d busca en /var/run/docker.sock  →  no existe  →  error
Con DOCKER_HOST →  K3d busca en el socket de Podman   →  existe     →  funciona
```

### Diagnóstico del socket de Podman

```bash
podman machine list
```

Resultado: `podman-machine-default` corriendo (Apple HV, 6 CPUs, 2GiB RAM, 100GiB disco).

```bash
podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}'
```

Resultado:

```
/var/folders/b3/20g4b2mj5m503ssk4m_n62kw0000gn/T/podman/podman-machine-default-api.sock
```

> **Nota:** Esta ruta en `/var/folders/` es generada por macOS por sesión. Puede cambiar entre reinicios del sistema.

### Configuración de DOCKER_HOST

```bash
export DOCKER_HOST=unix:///var/folders/b3/20g4b2mj5m503ssk4m_n62kw0000gn/T/podman/podman-machine-default-api.sock
```

### Eliminación del cluster Docker anterior

```bash
k3d cluster delete curso-k8s
```

### Eliminación del cluster Docker anterior

```bash
k3d cluster delete curso-k8s
```

### Creación del nuevo cluster sobre Podman

```bash
k3d cluster create curso-k8s --agents 2
```

Resultado: 1 Control Plane + 2 Agents, todos en estado `Ready`.

### Despliegue de Nginx sobre el nuevo cluster

```bash
kubectl apply -f kubernetes-lab/nginx-deployment.yaml
kubectl apply -f kubernetes-lab/nginx-service.yaml
kubectl apply -f kubernetes-lab/nginx-nodeport.yaml
```

Verificación:

```bash
kubectl get all
```

Los Pods arrancaron en estado `ContainerCreating` mientras descargaban la imagen `nginx:latest`, luego pasaron a `Running`.

### Validación del networking interno

```bash
kubectl run curlpod --rm -it --image=curlimages/curl -- sh
```

Dentro del Pod:

```sh
curl http://nginx-service
# Welcome to nginx!
```

Resultado: el cluster sobre Podman funciona de manera idéntica al cluster original con Docker.

---

## Sesión 3 — Port Forward, Escalado y Rolling Update

### Port Forward

Port Forward abre un túnel temporal entre la terminal local y un Service (o Pod) dentro del cluster. Es la forma más rápida de probar algo en desarrollo sin necesidad de exponer NodePorts ni configurar Ingress.

```bash
kubectl port-forward svc/nginx-service 8080:80
```

Esto mapea el puerto `80` del Service al puerto `8080` del host. Mientras el comando corre, `http://localhost:8080` responde con nginx. El tunnel se cierra al hacer `Ctrl+C`.

> **Cuándo usarlo:** desarrollo y debugging rápido. No es para producción.

---

## Próximos temas

### Escalado

```bash
kubectl scale deployment nginx --replicas=6
kubectl get pods -o wide
```

Resultado: 6 Pods distribuidos 2 por nodo (server-0, agent-0, agent-1).

> **Concepto:** el Scheduler distribuye réplicas de forma equilibrada entre los nodos disponibles.

```bash
kubectl scale deployment nginx --replicas=3
```

---

### Rolling Update y Rollback

Kubernetes reemplaza los Pods de a uno durante una actualización, garantizando que siempre haya réplicas disponibles (sin downtime).

Actualizar la imagen:

```bash
kubectl set image deployment/nginx nginx=nginx:1.25
```

Observar el progreso:

```bash
kubectl rollout status deployment/nginx
# Waiting for deployment "nginx" to finish: 1 out of 3 new replicas have been updated...
# deployment "nginx" successfully rolled out
```

Verificar la nueva imagen:

```bash
kubectl describe pods | grep Image:
```

Volver a la versión anterior (rollback):

```bash
kubectl rollout undo deployment/nginx
```

> **Concepto:** Kubernetes guarda el historial de revisiones del Deployment. `rollout undo` vuelve a la revisión inmediatamente anterior.

---

- [x] Port Forward
- [x] Escalado
- [x] Rolling Updates y Rollback

### ConfigMaps

Un ConfigMap almacena configuración (variables de entorno, archivos) fuera de la imagen. Permite cambiar configuración sin rebuilding la imagen.

Archivo: `kubernetes-lab/nginx-configmap.yaml`

```bash
kubectl apply -f kubernetes-lab/nginx-configmap.yaml
kubectl describe configmap nginx-config
```

El Deployment se actualizó para montar el `index.html` del ConfigMap como volumen en `/usr/share/nginx/html`, reemplazando la página por defecto de nginx.

```bash
kubectl apply -f kubernetes-lab/nginx-deployment.yaml
```

Validación con port-forward:

```bash
kubectl port-forward svc/nginx-service 8080:80 &
curl http://localhost:8080
kill %1
```

Resultado: nginx sirve el HTML definido en el ConfigMap (`Hola desde ConfigMap!`).

> **Concepto:** el ConfigMap se monta como volumen — si el ConfigMap cambia y se aplica, los Pods lo reflejan sin necesidad de reiniciarse (con un delay de sincronización).

---

### Secrets

Un Secret almacena datos sensibles (contraseñas, tokens, certificados). Kubernetes los codifica en base64 y los pasa a los Pods por memoria, sin escribirlos en disco.

> **Importante:** base64 no es encriptación. La seguridad real viene de los permisos RBAC que controlan quién puede leer Secrets en el cluster.

Crear un Secret:

```bash
kubectl create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password=MiPassword123
```

Ver cómo lo almacena Kubernetes (base64):

```bash
kubectl get secret db-credentials -o yaml
```

Decodificar un valor:

```bash
echo "YWRtaW4=" | base64 --decode
# admin
```

El Deployment se actualizó para inyectar el Secret como variables de entorno (`DB_USERNAME`, `DB_PASSWORD`):

```bash
kubectl apply -f kubernetes-lab/nginx-deployment.yaml
kubectl exec -it <pod> -- env | grep DB_
```

Resultado: las credenciales llegan al Pod sin estar hardcodeadas en la imagen ni en el manifiesto.

---

- [x] ConfigMaps y Secrets
### Namespaces

Los Namespaces son particiones lógicas del cluster para aislar recursos entre equipos, aplicaciones o ambientes (dev, staging, prod).

```bash
kubectl create namespace desarrollo
kubectl apply -f kubernetes-lab/nginx-deployment.yaml -n desarrollo
kubectl apply -f kubernetes-lab/nginx-service.yaml -n desarrollo
```

Verificación — los recursos están aislados entre namespaces:

```bash
kubectl get all -n desarrollo
kubectl get all -n default
```

Ver todos los pods de todos los namespaces:

```bash
kubectl get pods -A
```

> **Concepto:** el mismo manifiesto puede correr en distintos namespaces de forma completamente independiente. En la realidad cada namespace usaría imágenes o versiones diferentes según el ambiente.

---

- [x] Namespaces
### Ingress + Traefik

**Ingress** es una regla de enrutamiento HTTP. **Traefik** es el Ingress Controller (incluido en K3d/K3s) que lee esas reglas y enruta el tráfico real.

Para que Ingress funcione desde el host, el cluster debe crearse con el puerto 80 mapeado:

```bash
k3d cluster create curso-k8s --agents 2 --port "80:80@loadbalancer"
```

Agregar el dominio local al `/etc/hosts`:

```bash
echo "127.0.0.1 nginx.local" | sudo tee -a /etc/hosts
```

Archivo: `kubernetes-lab/nginx-ingress.yaml`

```bash
kubectl apply -f kubernetes-lab/nginx-ingress.yaml
kubectl get ingress
```

Flujo del tráfico:

```
http://nginx.local
    ↓ /etc/hosts → 127.0.0.1
    ↓ K3d loadbalancer (puerto 80)
    ↓ Traefik (lee regla Ingress: host nginx.local)
    ↓ nginx-service → Pods nginx
```

Resultado: `http://nginx.local` accesible desde el navegador de forma permanente, sin port-forward.

> **Concepto:** Traefik detecta cambios en los recursos Ingress automáticamente y actualiza su configuración sin reiniciarse.

---

- [x] Ingress + Traefik
### Helm

Helm es el gestor de paquetes de Kubernetes. Un **Chart** es un paquete de templates YAML con variables. Permite desplegar aplicaciones complejas con un solo comando y gestionar diferencias entre ambientes con `values.yaml`.

```
Chart (templates)  +  values.yaml  →  manifiestos finales  →  kubectl apply
```

Helm no interactúa con Docker ni Podman — solo habla con el API Server de Kubernetes.

Agregar repositorio y desplegar nginx:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install mi-nginx bitnami/nginx --namespace helm-demo --create-namespace
```

Ver todos los valores configurables del chart:

```bash
helm show values bitnami/nginx
```

Valores clave:
- `replicaCount` — número de réplicas (default: 1)
- `image.registry / repository / tag` — imagen a usar
- `service.type` — tipo de Service (default: LoadBalancer)

Actualizar valores sin tocar el chart:

```bash
helm upgrade mi-nginx bitnami/nginx --namespace helm-demo --set replicaCount=3
```

> **Concepto:** Helm calcula el diff entre el estado actual y el deseado, y aplica solo los cambios necesarios — igual que `kubectl apply` pero a nivel de release completo.

---

- [x] ArgoCD (pendiente práctica)
- [x] Helm
### Persistent Volumes

Los Pods son efímeros — al morir pierden todo lo escrito en disco. Los Persistent Volumes son storage que sobrevive al ciclo de vida de los Pods.

Tres objetos involucrados:
- **PV (PersistentVolume)** — el storage real, provisionado por el cluster
- **PVC (PersistentVolumeClaim)** — la solicitud del desarrollador ("necesito 100Mi")
- **Pod** — monta el PVC como un directorio

En K3d el provisioner `local-path` usa **late binding**: no crea el PV hasta que un Pod realmente monte el PVC.

Crear el PVC:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nginx-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
EOF
```

Estado inicial: `Pending` — nadie lo usa todavía, no hay PV.

Al aplicar el Deployment con el PVC montado en `/datos`, K3d creó el PV automáticamente y el PVC pasó a `Bound`.

Validación de persistencia:

```bash
# Escribir en el volumen
kubectl exec -it <pod> -- sh -c "echo 'datos persistentes' > /datos/test.txt"

# Eliminar el Pod (Kubernetes lo recrea automáticamente)
kubectl delete pod <pod>

# Verificar que los datos sobrevivieron
kubectl exec -it <nuevo-pod> -- cat /datos/test.txt
# datos persistentes
```

> **Concepto clave:** el PV vive independientemente de los Pods. Aunque borres el Deployment, los datos persisten hasta que eliminés el PVC explícitamente.

---

- [x] Persistent Volumes
