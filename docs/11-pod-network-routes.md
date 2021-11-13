# Provisioning Pod Network Routes

[Guide](https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/11-pod-network-routes.md)

## The Routing Table

```sh
for instance in worker-0 worker-1 worker-2; do
  instance_id_ip="$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${instance}" \
    --output text --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress]')"
  instance_id="$(echo "${instance_id_ip}" | cut -f1)"
  instance_ip="$(echo "${instance_id_ip}" | cut -f2)"
  pod_cidr="$(aws ec2 describe-instance-attribute \
    --instance-id "${instance_id}" \
    --attribute userData \
    --output text --query 'UserData.Value' \
    | base64 --decode | tr "|" "\n" | grep "^pod-cidr" | cut -d'=' -f2)"
  echo "${instance_ip} ${pod_cidr}"

  aws ec2 create-route \
    --route-table-id "${ROUTE_TABLE_ID}" \
    --destination-cidr-block "${pod_cidr}" \
    --instance-id "${instance_id}"
done
```

## Routes

The last command above (i.e. `aws ec2 create-route`) creates the route for each
worker.

```sh
aws ec2 describe-route-tables \
  --route-table-ids "${ROUTE_TABLE_ID}" \
  --query 'RouteTables[].Routes'
```

Next: [Deploying the DNS Cluster Add-on](12-dns-addon.md)
