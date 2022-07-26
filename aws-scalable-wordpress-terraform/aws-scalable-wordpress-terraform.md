# What's in the infrastructure? 
- High availability: 
  - EC2: 
    Two Wordpress EC2 sitting in two availability zones.
  - RDS:
    The RDS has multi-az enabled. There will be a main and a standby RDS instances across availability zones. 
- Scalability: 
  The two EC2 are behind an autoscaling group that automatically scales out the number of EC2 by adding maximum 2 more EC2 when the existing EC2 are low in capacity. 
- Load balancing: 
  The ALB balances the traffic load between the two default EC2's. 
- Security:
  - EC2: 
    The internet traffic first reaches the ALB before arriving at EC2. EC2's are only open port 80 to the ALB. No public traffic can reach EC2's directly. 
  - RDS:
    The RDS only accepts internal traffic from EC2's. The only route to access the RDS is from the EC2's.
  - S3: 
    Role-based access control is in place. Only EC2 can access the S3 bucket storing static assets of the wordpress server. Only Cloudtrail can access the S3 bucket storing the trail data, etc.
  - IAM:
    One IAM user is created with the permissions to work with EC2, ALB, Autoscaling, RDS, and S3. No permissions of security or networking related granted. 

# Future improvements
- To use custom AMI image:
  Currently the Wordpress image is provided by Amazon Marketplace from VMWare. To have better control and more flexibility, it's feasible to create a custom private image of Wordpress and use it instead.
- Once the website domain name is confirmed, we can create a SSL certificate in ACM and attach it to the ALB for SSL offloading. SSL offloading on ALB can reduce the consumption of computing resources on the EC2's. 
- To add more logic to ensure EC2's sit in different availability zones, instead of randomly select an AZ. 