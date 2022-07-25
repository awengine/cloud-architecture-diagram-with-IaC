# cloud-architecture-diagram-with-IaC
A collection of cloud architecture diagrams and the corresponding IaC templates.

## How to Use
0. Ensure your working environment has configured with the cloud provider and IaC provider you're going to use, e.g. AWS and Cloudformation
1. In ./diagrams, select an architecture diagram you plan to use, e.g. aws-scalable-wordpress-cloudformation. The last word is the IaC provider. 
2. In ./cloudformation, find the corresponding template with the same file name. 
3. Run the template, which will call the dependencies automatically if needed.
