#   EKS Terraform

This repo contains Terraform assets to create an EKS cluster designed to showcase the webMethods products in such an environment.

The cluster is configured as follows:
-   kubernetes version is specified in variable cluster_version (default 1.30)
-   cluster name starts with "eks" followed by a random string
-   it is placed in a region specified in the region variable (default eu-central-1)
-   it is created in an already existing vpc, which is specified using the vpc_id variable
-   3 private and 3 public subnets are created, using a CIDR ranges provided in private_subnet_cidrs and public_subnet_cidrs (lists)
-   two node groups are created
-   the nodes ami type and instance type are specified in variables ami_type and instance_type (defaults AL2_x86_64 and t3.small)
-   the aws-ebs-csi-driver and aws-mountpoint-s3-csi-driver addons are installed and configured
-   an nginx load bamancer is installed and configured
-   trafic to RDS is authorized by configuring an ingress rule for the node groups' security group. The RDS security group id and port are provided in the rds_security_group_id and rds_allowed_port variables  

An example of tfvars file is provided (see sandbox.tfvars.example), you can rename it into sandbox.tfvars and adapt the values.  

You need to have terraform, helm and the aws cli installed and configured for all this to work.  

To create the cluster:
```
terraform init
terraform plan
terraform apply -var-file="sandbox.tfvars"
```
The apply command will take several minutes.  

Then you can configure kubectl to connect to the cluster using this command:
```
aws eks --region $(terraform output -raw region) update-kubeconfig \
    --name $(terraform output -raw cluster_name)
```
To check the kubectl configuration, use:
```
kubectl get nodes
```

Once you've finished working with the cluster:
```
terraform destroy -target=helm_release.nginx_ingress -var-file="sandbox.tfvars"
terraform destroy -var-file="sandbox.tfvars"
```
These commands will take several minutes.  
Note: a one step destruction isn't possible. It would require a dependency in the public subnet definition which introduced a circular dependency.