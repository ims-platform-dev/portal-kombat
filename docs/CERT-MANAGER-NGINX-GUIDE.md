# Using cert-manager with nginx-ingress for TLS

Complete guide on how nginx-ingress and cert-manager work together for automatic TLS certificate management.

## Architecture Overview

```
Internet → NLB (TCP passthrough) → nginx-ingress (TLS termination) → Backend Service
                                          ↑
                                    cert-manager
                                    (manages certificates)
```

### How It Works

1. **NLB (Network Load Balancer)**:
   - Passes TCP traffic through (no TLS termination)
   - Simple Layer 4 load balancing
   - Configured with `backend-protocol: tcp`

2. **nginx-ingress Controller**:
   - Receives encrypted TLS traffic
   - Terminates TLS using certificates from Kubernetes secrets
   - Routes decrypted traffic to backend services

3. **cert-manager**:
   - Watches Ingress resources
   - Automatically requests certificates from Let's Encrypt
   - Stores certificates in Kubernetes secrets
   - Automatically renews certificates before expiry

## Why This Approach vs ACM?

### ✅ Advantages of cert-manager:

1. **Kubernetes-Native**: Everything managed via K8s manifests
2. **Multiple Certificate Authorities**: Let's Encrypt, self-signed, private CA
3. **Automatic Renewal**: No manual intervention needed
4. **Free**: No AWS costs for certificates
5. **Portable**: Works on any Kubernetes cluster (not AWS-specific)
6. **Flexible**: Can use DNS01 or HTTP01 challenges
7. **Wildcard Support**: Easy wildcard certificates with DNS01

### ❌ Disadvantages vs ACM:

1. **TLS at Application Layer**: Slightly more CPU usage on nginx pods
2. **Certificate Storage**: Secrets stored in etcd (needs backup)
3. **Initial Setup**: Requires cert-manager deployment

## Configuration Explained

### nginx-ingress Configuration

The key configuration in `environments/dev/platform/nginx-ingress/values.yaml`:

```yaml
# NLB passes TCP traffic through (no TLS termination at load balancer)
service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"

# nginx-ingress SSL/TLS configuration
config:
  ssl-protocols: "TLSv1.2 TLSv1.3"
  ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384"

  # Force HTTPS redirect
  force-ssl-redirect: "true"
  ssl-redirect: "true"

  # HSTS security headers
  hsts: "true"
  hsts-max-age: "31536000"
  hsts-include-subdomains: "true"
```

**What this does:**
- NLB forwards encrypted traffic to nginx-ingress pods
- nginx-ingress terminates TLS using certificates from secrets
- Forces HTTP → HTTPS redirect
- Adds HSTS headers for security

## Using cert-manager with Ingress

### Method 1: Ingress Annotations (Recommended)

This is the simplest method - cert-manager watches for these annotations:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
  annotations:
    # Specify IngressClass
    kubernetes.io/ingress.class: nginx

    # cert-manager annotations
    cert-manager.io/cluster-issuer: letsencrypt-prod  # Use production Let's Encrypt
    # OR for testing: cert-manager.io/cluster-issuer: letsencrypt-staging

    # Optional: Specify challenge type (default is http01)
    # cert-manager.io/acme-challenge-type: http01
spec:
  tls:
  - hosts:
    - myapp.plt-dev.inteleradhealth.com
    secretName: myapp-tls  # cert-manager will create this secret
  rules:
  - host: myapp.plt-dev.inteleradhealth.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

**What happens:**
1. You create the Ingress resource
2. cert-manager sees the annotation
3. cert-manager creates a Certificate resource
4. cert-manager requests certificate from Let's Encrypt
5. Let's Encrypt validates via HTTP01 challenge (hits `/.well-known/acme-challenge/`)
6. cert-manager stores certificate in the specified secret (`myapp-tls`)
7. nginx-ingress uses the certificate from the secret
8. Your app is now accessible via HTTPS!

### Method 2: Explicit Certificate Resource

For more control, create a Certificate resource directly:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-cert
  namespace: default
spec:
  secretName: myapp-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - myapp.yourcompany.com
  - www.myapp.yourcompany.com
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  tls:
  - hosts:
    - myapp.yourcompany.com
    - www.myapp.yourcompany.com
    secretName: myapp-tls  # References the certificate secret
  rules:
  - host: myapp.yourcompany.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

## Complete Example: Port.io Webhook

Here's a complete example for Port.io webhooks with automatic TLS:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: port-webhook
  namespace: port
spec:
  selector:
    app: port-webhook
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: port-webhook
  namespace: port
spec:
  replicas: 2
  selector:
    matchLabels:
      app: port-webhook
  template:
    metadata:
      labels:
        app: port-webhook
    spec:
      containers:
      - name: webhook
        image: your-webhook-image:latest
        ports:
        - containerPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: port-webhook
  namespace: port
  annotations:
    # Use public nginx-ingress
    kubernetes.io/ingress.class: nginx

    # cert-manager - automatic TLS certificate
    cert-manager.io/cluster-issuer: letsencrypt-prod

    # Rate limiting for webhook
    nginx.ingress.kubernetes.io/limit-rps: "100"
    nginx.ingress.kubernetes.io/limit-connections: "50"
spec:
  tls:
  - hosts:
    - webhooks.portal-kombat.yourcompany.com
    secretName: port-webhook-tls
  rules:
  - host: webhooks.portal-kombat.yourcompany.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: port-webhook
            port:
              number: 80
```

**Result:**
- Accessible at: `https://webhooks.portal-kombat.yourcompany.com`
- Certificate automatically issued by Let's Encrypt
- Certificate automatically renewed before expiry
- DNS record automatically created by external-dns

## Wildcard Certificates

For wildcard certificates (e.g., `*.yourcompany.com`), you need DNS01 challenge:

### Step 1: Update ClusterIssuer for DNS01

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod-dns
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: austin.carter@intelerad.com
    privateKeySecretRef:
      name: letsencrypt-prod-dns
    solvers:
    - dns01:
        route53:
          region: us-east-2
          # Use same IAM role as external-dns or create dedicated role
          # Requires Route53 permissions
      selector:
        dnsZones:
        - yourcompany.com
```

### Step 2: Create Wildcard Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-cert
  namespace: default
spec:
  secretName: wildcard-tls
  issuerRef:
    name: letsencrypt-prod-dns
    kind: ClusterIssuer
  dnsNames:
  - "*.yourcompany.com"
  - yourcompany.com
```

### Step 3: Use Wildcard Certificate in Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  tls:
  - hosts:
    - app1.yourcompany.com
    - app2.yourcompany.com
    secretName: wildcard-tls  # Shared wildcard certificate
  rules:
  - host: app1.yourcompany.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app1
            port:
              number: 80
  - host: app2.yourcompany.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app2
            port:
              number: 80
```

## Internal Services with Self-Signed Certificates

For internal services (Grafana, ArgoCD, Prometheus), use self-signed certificates:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    # Use internal nginx-ingress
    kubernetes.io/ingress.class: nginx-internal

    # Use self-signed issuer
    cert-manager.io/cluster-issuer: selfsigned
spec:
  tls:
  - hosts:
    - grafana.portal-internal.yourcompany.com
    secretName: grafana-tls
  rules:
  - host: grafana.portal-internal.yourcompany.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 80
```

## Troubleshooting

### Certificate Not Being Issued

```bash
# Check Certificate status
kubectl get certificate -n default

# Describe Certificate to see events
kubectl describe certificate myapp-tls -n default

# Check CertificateRequest
kubectl get certificaterequest -n default
kubectl describe certificaterequest <name> -n default

# Check Challenge (for ACME)
kubectl get challenge -n default
kubectl describe challenge <name> -n default

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100
```

**Common Issues:**

1. **HTTP01 Challenge Failing**
   ```
   Error: Waiting for HTTP-01 challenge propagation
   ```
   **Fix:** Ensure nginx-ingress is accessible from the internet
   ```bash
   # Test ingress accessibility
   curl -I http://myapp.yourcompany.com/.well-known/acme-challenge/test
   ```

2. **DNS Not Resolving**
   ```
   Error: Could not resolve host
   ```
   **Fix:** Ensure external-dns created the DNS record
   ```bash
   # Check external-dns logs
   kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

   # Verify DNS record
   dig myapp.yourcompany.com
   ```

3. **Rate Limiting from Let's Encrypt**
   ```
   Error: too many certificates already issued
   ```
   **Fix:** Use staging issuer for testing
   ```yaml
   cert-manager.io/cluster-issuer: letsencrypt-staging
   ```

### Certificate Renewal Issues

Certificates should automatically renew 30 days before expiry.

```bash
# Check certificate expiry
kubectl get certificate -n default -o custom-columns=\
NAME:.metadata.name,\
READY:.status.conditions[0].status,\
EXPIRY:.status.notAfter

# Force renewal (delete secret)
kubectl delete secret myapp-tls -n default
# cert-manager will automatically recreate it
```

### Ingress Not Using Certificate

```bash
# Check secret exists and has correct data
kubectl get secret myapp-tls -n default -o yaml

# Should contain:
# - tls.crt (certificate)
# - tls.key (private key)
# - ca.crt (CA certificate)

# Check nginx-ingress is using the certificate
kubectl exec -n ingress-nginx <nginx-pod> -- cat /etc/nginx/nginx.conf | grep ssl_certificate

# Test TLS connection
openssl s_client -connect myapp.yourcompany.com:443 -servername myapp.yourcompany.com
```

## Monitoring Certificate Expiry

### Prometheus Alerts

If using Prometheus, cert-manager exports metrics:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cert-manager-alerts
  namespace: cert-manager
spec:
  groups:
  - name: cert-manager
    interval: 1m
    rules:
    - alert: CertificateExpiringSoon
      expr: certmanager_certificate_expiration_timestamp_seconds - time() < 604800
      for: 1h
      labels:
        severity: warning
      annotations:
        summary: "Certificate {{ $labels.name }} expiring soon"
        description: "Certificate {{ $labels.name }} in {{ $labels.namespace }} expires in less than 7 days"

    - alert: CertificateNotReady
      expr: certmanager_certificate_ready_status{condition="False"} == 1
      for: 10m
      labels:
        severity: critical
      annotations:
        summary: "Certificate {{ $labels.name }} not ready"
        description: "Certificate {{ $labels.name }} in {{ $labels.namespace }} is not ready"
```

### Check All Certificates

```bash
# List all certificates with status
kubectl get certificates --all-namespaces

# Get detailed expiry info
kubectl get certificates --all-namespaces -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
READY:.status.conditions[0].status,\
SECRET:.spec.secretName,\
ISSUER:.spec.issuerRef.name,\
EXPIRY:.status.notAfter
```

## Best Practices

1. **Use Staging for Testing**
   - Always test with `letsencrypt-staging` first
   - Let's Encrypt has rate limits (50 certs per domain per week)

2. **One Certificate Per Ingress**
   - Don't share secrets between namespaces
   - Use separate certificates for better isolation

3. **Monitor Certificate Expiry**
   - Set up Prometheus alerts
   - Check cert-manager metrics regularly

4. **Backup Certificates**
   - Include TLS secrets in Velero backups
   - Document ClusterIssuer configurations

5. **Use Wildcard Certificates Sparingly**
   - DNS01 challenge is more complex
   - Increases blast radius if compromised
   - Good for many subdomains under same zone

6. **Separate Public and Internal**
   - Use `nginx` IngressClass for public services
   - Use `nginx-internal` IngressClass for internal services
   - Use appropriate ClusterIssuers (Let's Encrypt vs self-signed)

## Summary

✅ **nginx-ingress + cert-manager Setup:**
- NLB configured for TCP passthrough
- nginx-ingress handles TLS termination
- cert-manager manages certificate lifecycle
- Automatic certificate issuance and renewal
- No ACM needed - fully Kubernetes-native

✅ **Benefits:**
- Zero-touch TLS for new services
- Automatic DNS record creation (via external-dns)
- Automatic certificate renewal
- Works across any cloud or on-prem
- No additional AWS costs

✅ **Next Steps:**
1. Deploy platform services via ArgoCD
2. Create test Ingress with cert-manager annotation
3. Verify certificate issuance
4. Deploy Port.io webhooks with automatic TLS
