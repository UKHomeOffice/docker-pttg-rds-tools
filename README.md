# docker-pttg-rds-tools
## AWS CLI based tools for RDS.

This is currently used only for starting an RDS instance if it is not started, and so this is the 
entrypoint of the container. Remove the entrypoint if this is ever expaneded with more functions.

### Drone variables:
* DOCKER_PASSWORD - the password for the quay robot used to deploy to quay. 

## start-rds.sh
Checks if the RDS instance is available, and if not then attempts to start it and waits for 
the instance to become available.

This is useful for making sure that the RDS instance is up before deploying to a test environment.

### Runtime Environment variables:
* RDS_INSTANCE - the name of the RDS instance to start.
