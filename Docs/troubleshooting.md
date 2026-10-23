# Troubleshooting

This guide helps diagnose problems with the deployed application. It starts with the tools and log locations, then covers each failure area in the order in which a request and a deployment can break, and includes the frontend container incident as a case study. Commands match the files in this repository; replace each `<placeholder>` with your own value and never paste secrets into logs or screenshots.

Related documents: [README](../README.md), [architecture](architecture.md), [deployment guide](deployment-guide.md), [testing and validation](testing-and-validation.md).

## Contents

- [Diagnostic Toolbox](#diagnostic-toolbox)
- [1. Docker Containers Not Starting](#1-docker-containers-not-starting)
- [2. Docker Image Pull Failures](#2-docker-image-pull-failures)
- [3. EC2 User-Data Failures](#3-ec2-user-data-failures)
- [4. Case Study: Frontend Container Not Created](#4-case-study-frontend-container-not-created)
- [5. Nginx 301 Redirects and 502 Errors](#5-nginx-301-redirects-and-502-errors)
- [6. HTTP 404 Responses from Express](#6-http-404-responses-from-express)
- [7. Empty Product Catalog](#7-empty-product-catalog)
- [8. MongoDB Atlas Connectivity and Access-List Issues](#8-mongodb-atlas-connectivity-and-access-list-issues)
- [9. Secrets Manager Permissions and Missing Secret Values](#9-secrets-manager-permissions-and-missing-secret-values)
- [10. Security Group and Route-Table Issues](#10-security-group-and-route-table-issues)
- [11. SSH Timeouts](#11-ssh-timeouts)
- [12. PEM File Permission Errors Under WSL](#12-pem-file-permission-errors-under-wsl)
- [13. Terraform Plans That Replace EC2 Instances](#13-terraform-plans-that-replace-ec2-instances)
- [14. Inspecting Logs and Recovering Safely](#14-inspecting-logs-and-recovering-safely)
- [15. Symptom Quick Reference](#15-symptom-quick-reference)

## Diagnostic Toolbox

What you can reach depends on the instance:

- **Frontend instance:** reachable over SSH once you add a temporary TCP 22 rule (see the [deployment guide](deployment-guide.md#15-ssh-into-the-frontend-instance)). Docker and log commands work there.
- **Backend instance:** not reachable over SSH with the current security group rules. Use its boot output, HTTP responses from the frontend instance and the API error messages instead.

| Need | Command | Run on |
| --- | --- | --- |
| Output of the user-data script | `sudo tail -n 100 /var/log/cloud-init-output.log` | Frontend instance |
| Did cloud-init finish or fail | `cloud-init status --long` | Frontend instance |
| Boot output without SSH | `aws ec2 get-console-output --region ap-south-1 --instance-id <instance-id> --latest --output text` | Your machine |
| All containers, including stopped ones | `sudo docker ps -a` | Frontend instance |
| Container logs | `sudo docker logs <container-name> --tail 100` | Frontend instance |
| Why a container stopped | `sudo docker inspect <container-name> --format '{{.State.Status}} exit={{.State.ExitCode}} {{.State.Error}}'` | Frontend instance |
| Docker daemon health | `sudo systemctl status docker` and `sudo journalctl -u docker --no-pager \| tail -50` | Frontend instance |
| Rendered Nginx configuration | `sudo docker exec ecommerce-frontend cat /etc/nginx/conf.d/default.conf` and `sudo docker exec ecommerce-frontend nginx -t` | Frontend instance |
| HTTP request with redirects and headers | `curl -iL <url>` (add `-v` for detail) | Anywhere |
| TCP reachability | `nc -zv -w 3 <backend-private-ip> <port>` | Frontend instance |
| User-data delivered to the instance | The two commands below | The instance |
| Planned infrastructure changes | `terraform plan` and `terraform state list` | Your machine |

To read the user-data that EC2 delivered (instance metadata version 2):

```bash
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/user-data
```

## 1. Docker Containers Not Starting

**Symptoms:** a container is missing from `sudo docker ps -a`, shows `Exited`, or keeps showing `Restarting`.

| Observation | Likely cause | What to do |
| --- | --- | --- |
| The container does not exist at all | `docker run` never ran or failed before creating the container (user-data stopped earlier, or the command was malformed) | Read `/var/log/cloud-init-output.log`; see sections 3 and 4 |
| `Exited` right after start | The process crashed. Read `sudo docker logs <name>`. | Fix the reported error (for example a database connection error, see section 8) |
| `Restarting` repeatedly | The containers use `--restart unless-stopped`, so Docker restarts a process that keeps exiting | The logs show the underlying error; fix that first |
| `exec format error` in the logs | The image was built for another CPU architecture (for example arm64) and the instance is x86_64 | Rebuild with `--platform linux/amd64` and push again (deployment guide, section 3) |
| `Conflict. The container name "/<name>" is already in use` when re-running a command by hand | A container with that name already exists | `sudo docker rm -f <name>` and run the command again |
| `Bind for 0.0.0.0:80 failed: port is already allocated` | Another container or process already uses the port | Find it with `sudo docker ps` and stop it |
| Every Docker command fails | The Docker daemon is not running | `sudo systemctl status docker`, then `sudo systemctl start docker` |

## 2. Docker Image Pull Failures

The instances pull images from Docker Hub without logging in (`docker pull <dockerhub-username>/ecommerce-...:latest`).

| Message (wording varies by Docker version) | Cause | Fix |
| --- | --- | --- |
| `pull access denied ... repository does not exist or may require 'docker login'` | Wrong image name or Docker Hub user, or the repository is private | Check `var.dockerhub_username` and the repository name; make the repository public |
| `manifest ... not found` | The `latest` tag was never pushed | Push the image (deployment guide, section 4) |
| `toomanyrequests: You have reached your pull rate limit` | Anonymous pulls are rate limited per source address, and the backend shares the NAT Gateway address | Wait and retry, or authenticate pulls |
| Timeouts or connection errors | No outbound path: the route table, NAT Gateway or security group egress | See section 10 |

Checks:

- From any machine: `docker logout` and `docker pull <dockerhub-username>/ecommerce-frontend:latest`. If this fails, the repository is not public.
- On the frontend instance, run the failing `sudo docker pull ...` by hand to see the exact error.
- For the backend, confirm that the private route table points `0.0.0.0/0` to an `available` NAT Gateway (section 10).

## 3. EC2 User-Data Failures

How user-data behaves in this project:

- cloud-init runs the script once, at the first boot of an instance, as root. Its output goes to `/var/log/cloud-init-output.log`.
- Both scripts start with `set -eu`. The first failing command ends the script, and nothing after it runs. For example, a failed secret lookup means no backend container is ever started.
- Editing `user_data` in Terraform later does not run the script again on an existing instance (section 13).

How to find the failing command:

1. On the frontend instance: `cloud-init status --long` (a failed script is reported as an error) and `sudo tail -n 100 /var/log/cloud-init-output.log`.
2. For the backend, use the console output command from the toolbox. It shows boot messages and may include the script output.
3. Match the last output against the list below.

Common causes in this project:

| Cause | Evidence | Section |
| --- | --- | --- |
| Malformed command | Docker prints a usage error | 4 |
| No internet access during boot (`yum install`, `docker pull`, secret lookup) | Timeouts or "could not resolve host" errors. The backend instance resource depends only on the IAM role policy; it has no dependency on the NAT Gateway or the private route table association, so on a fast boot the route may not exist yet. This has not been observed in this deployment. | 10 |
| Secret missing, wrong name or access denied | `ResourceNotFoundException` or `AccessDeniedException` from the AWS CLI | 9 |
| A key is missing from the secret, or the secret is not JSON | `jq` prints an error and exits | 9 |
| The script was run a second time by hand | `docker network create` fails because `ecommerce-network` already exists, and `set -e` stops the script | Run only the commands that did not complete |

Recovery: either run the missing commands by hand (a manual fix that exists only on that instance) or replace the instance so the script runs again from the start (deployment guide, section 17).

## 4. Case Study: Frontend Container Not Created

### 4.1 Summary

| Item | Detail |
| --- | --- |
| Symptom | After `terraform apply`, the frontend instance was running but no `ecommerce-frontend` container had been created, so nothing was serving the website on port 80. |
| Where | The frontend `user_data` in `terraform/main.tf` |
| Root cause | A missing space in the `docker run` command, which left the command without an image argument |
| Introduced in | Commit `70e3a92` (Add Docker and Terraform deployment configuration) |
| Corrected in | Commit `2fdc162` (Updated some terraform configurations) |

### 4.2 Root cause

The line in commit `70e3a92`:

```text
docker run -d --name ecommerce-frontend --restart unless-stopped -p 80:80 -e BACKEND_PRIVATE_IP="${aws_instance.backend.private_ip}"${var.dockerhub_username}/ecommerce-frontend:latest
```

There is no space between the closing quote of the IP address and the image name. After Terraform substitutes the values, the instance receives:

```text
docker run -d --name ecommerce-frontend --restart unless-stopped -p 80:80 -e BACKEND_PRIVATE_IP="<backend-private-ip>"akash0505/ecommerce-frontend:latest
```

Bash joins a quoted string and the text that touches it into a single word. The command therefore has these arguments:

| Argument | Role |
| --- | --- |
| `-d` | Run detached |
| `--name ecommerce-frontend` | Container name |
| `--restart unless-stopped` | Restart policy |
| `-p 80:80` | Publish port 80 |
| `-e` followed by `BACKEND_PRIVATE_IP=<backend-private-ip>akash0505/ecommerce-frontend:latest` | The whole joined word is consumed as the value of `-e` |
| (nothing) | The required image argument is missing |

`docker run` needs an image name, so it fails without creating a container. The earlier lines of the script (installing Docker, starting it and `docker pull`) are separate, correct commands, so the image was downloaded but never started. Because the script runs with `set -eu`, the failing command ends it.

This mistake is valid shell syntax, so neither `terraform validate` nor a syntax check (`bash -n`) can detect it. It only shows up when the command runs.

### 4.3 Evidence

- **Git history:** the malformed line is in commit `70e3a92` and the corrected line is in commit `2fdc162` (`git show 2fdc162 -- terraform/main.tf`).
- **Container state:** on the frontend instance `sudo docker ps -a` did not list `ecommerce-frontend` (reported by the author), while `sudo docker images` would list the pulled image.
- **cloud-init log:** `/var/log/cloud-init-output.log` is where the failure is recorded. Expect a Docker usage error saying that `docker run` requires an image argument, followed by a note that the user-data script failed. The exact wording depends on the Docker and cloud-init versions, so capture the real output.

> **Screenshot placeholder (not yet captured): cloud-init log of the failed `docker run`.**
> What it demonstrates: the Docker error recorded in the cloud-init log when the user-data `docker run` command had no image argument.
> Capture the relevant part of `/var/log/cloud-init-output.log` from the original frontend instance, if it is still available. Save it as `docs/screenshots/cloud-init-malformed-docker-run.png`, then uncomment the image line below.
>
> <!-- ![cloud-init log showing the failed docker run command](screenshots/cloud-init-malformed-docker-run.png) -->

### 4.4 Manual recovery

A running frontend instance can be repaired without replacing it. On the frontend instance (over SSH):

1. Confirm the situation: `sudo docker ps -a` shows no `ecommerce-frontend` container, and `sudo docker images` shows the frontend image.
2. Get the backend's private IP from the EC2 console, or:

   ```bash
   aws ec2 describe-instances --region ap-south-1 \
     --filters "Name=tag:Name,Values=ecommerce-backend" "Name=instance-state-name,Values=running" \
     --query "Reservations[].Instances[].PrivateIpAddress" --output text
   ```

3. Start the container with the corrected command:

   ```bash
   sudo docker run -d --name ecommerce-frontend --restart unless-stopped -p 80:80 \
     -e BACKEND_PRIVATE_IP="<backend-private-ip>" \
     akash0505/ecommerce-frontend:latest
   ```

4. Verify: `sudo docker ps`, then `curl -I http://localhost` on the instance, then the public address in a browser.

This is a stopgap. It exists only on that instance and is not recorded in Terraform, and the instance still carries the faulty user-data.

### 4.5 Permanent Terraform correction

Commit `2fdc162` adds the missing space. The final configuration, confirmed from the current `terraform/main.tf`:

```text
docker run -d --name ecommerce-frontend --restart unless-stopped -p 80:80 -e BACKEND_PRIVATE_IP="${aws_instance.backend.private_ip}" ${var.dockerhub_username}/ecommerce-frontend:latest
```

The same commit also made these changes:

- Adds `key_name = var.key_pair_name` to both instances and defines the `key_pair_name` variable (default `devops`).
- Adds the outputs `frontend_public_ip` and `frontend_public_dns`.
- Removes a leading blank line from `frontend/default.conf.template`.

Why the fix needs a new instance: cloud-init runs user-data only at the first boot of an instance, so an instance that already booted with the faulty script does not run the corrected one. Adding `key_name` to an existing instance forces Terraform to replace it (a key pair cannot be changed on a running instance), so applying this commit plans a replacement of both instances. The new frontend instance executes the corrected script on its first boot. See section 13.

### 4.6 Prevention

- Put one argument per line with a trailing `\`, as the backend script does. A missing space is easy to see that way.
- After the first boot of any instance, run `sudo docker ps -a` and read the end of `/var/log/cloud-init-output.log` before testing the application.
- The frontend `user_data` is shown as `(known after apply)` in `terraform plan` because it embeds the backend's private IP. Read the rendered script from the instance metadata (toolbox) after the instance is created.

### 4.7 Other `docker run` mistakes to recognize

| Message or behavior | Usual cause |
| --- | --- |
| `docker run` requires at least 1 argument | No image argument, for example because `-e` absorbed it, as in this incident |
| `invalid reference format` | The image name is malformed: stray characters, uppercase letters, or an empty variable that leaves a name such as `/ecommerce-frontend:latest` |
| `unknown shorthand flag` or `unknown flag` | A typo, or an option placed after the image name, where Docker treats it as an argument for the container |
| A second line runs as its own command and fails with `command not found` | A line continuation backslash is missing or has a trailing space after it |
| `Conflict. The container name ... is already in use` | A container with that name already exists |
| `Bind for 0.0.0.0:<port> failed: port is already allocated` | The host port is already in use |

## 5. Nginx 301 Redirects and 502 Errors

### 301 Moved Permanently on an API path

A `301` on `/api/...` comes from Nginx and is not an error. For a location that ends in `/` and uses `proxy_pass`, Nginx redirects the same path without the slash to the path with it. In this configuration the locations `/api/auth/`, `/api/users/`, `/api/products/`, `/api/cart/`, `/api/orders/` and `/api/payments/` behave this way; `/api/categories` has no trailing slash and does not redirect.

- Observed: `GET /api/products` returns `301` to `/api/products/`, then `200`.
- Check: `curl -i http://<frontend-public-ip>/api/products` shows the `Location` header; `curl -iL ...` follows it.
- A browser follows a redirected `GET` automatically. A redirected `POST` is repeated as a `GET` without its body, so write requests must use the exact prefix path that ends in `/` (for example `POST /api/products/`). The checkout request `POST /api/orders` is affected by this (see [known limitations](testing-and-validation.md#known-limitations)).

### 502 Bad Gateway

Nginx could not get a valid answer from the backend. A connection that times out normally produces `504 Gateway Time-out`.

| Cause | How to recognize it | Fix |
| --- | --- | --- |
| The backend container is not running or has not started yet | `sudo docker logs ecommerce-frontend --tail 100` shows `connect() failed (111: Connection refused) while connecting to upstream`; the port check (testing procedure 4) is refused | Wait for the backend user-data to finish; check sections 1, 3, 8 and 9 |
| The frontend container has a stale or wrong backend IP | The `proxy_pass` lines in the rendered configuration do not match the backend instance's current private IP | Compare `sudo docker exec ecommerce-frontend grep proxy_pass /etc/nginx/conf.d/default.conf` with the backend's private IP; recreate the container with the right IP (deployment guide, section 17) |
| A security group or route blocks the connection | The port check times out and Nginx reports `110: Connection timed out` | Section 10 |
| The backend service is up but returns an error | The status code is not 502; the body is the service's JSON error | Read the message (sections 6 to 8) |

Related behaviors:

- A static page (`curl -I http://<frontend-public-ip>`) can return `200` while every API call fails, because Nginx serves the React files itself.
- An `/api/...` request that returns the React HTML page instead of JSON did not match any Nginx location (for example a path with a different prefix), so it fell back to `index.html`.
- `/health` on the frontend address returns the React page. The service health endpoints exist only on the backend instance.

## 6. HTTP 404 Responses from Express

When no route matches, Express answers with a plain `404` page of the form `Cannot GET /path`. That is different from a service answering `404` with a JSON `message` (for example `Order not found`), which means the route exists but the record does not.

| Cause | Example | Fix |
| --- | --- | --- |
| The path is a base path without a handler | `GET /`, `GET /api/auth/`, `GET /api/cart/`, `GET /api/orders/` | Expected. Test a real route such as `/api/cart/<userId>` or `/api/orders/user/<userId>` |
| Wrong HTTP method | `GET /api/auth/login` (the route accepts `POST`) | Use the method listed in [architecture.md](architecture.md#6-backend-services) |
| Wrong service or port | `/api/cart/<userId>` sent to port 3002 | Each service serves only its own prefixes |
| Wrong prefix or typo | `/api/product/` instead of `/api/products/` | Compare with the routes table |
| Missing path parameter | `/api/cart/` without a user id | Add the id |

Observed: requests to `/`, `/api/auth/`, `/api/cart/` and `/api/orders/` returned `404`. This matches the route definitions and is not evidence that a service is disconnected.

## 7. Empty Product Catalog

Symptom: `GET /api/products` returns `{"products":[],"totalPages":0,"currentPage":1,"total":0}` and the Products page shows nothing.

This is a successful response. The product service reached MongoDB, and the database has no matching documents. Common reasons:

- The Atlas database is new and the repository has no seed script.
- Atlas creates the `ecommerce_products` database and its collections only after the first write, so they will not appear in the Atlas console yet.
- The list query only returns products whose `isActive` field is true, and it applies any `category`, `minPrice`, `maxPrice`, `search` or `featured` parameters from the request.

To confirm that the pipeline works, create test data (see [testing-and-validation.md](testing-and-validation.md#9-product-endpoint-response-and-the-empty-catalog)) and list the products again. Remember that the product write endpoints are unauthenticated.

## 8. MongoDB Atlas Connectivity and Access-List Issues

Backend connections to Atlas leave through the NAT Gateway, so Atlas must allow the NAT Gateway's Elastic IP. Registration and login worked in the deployed environment, which shows that the user service reached Atlas.

How a connection problem shows up:

- API calls that touch the database return `500` with `"message":"Server error"` and an `error` text. A typical text for a missing connection is `Operation ... buffering timed out after 10000ms`.
- Mongoose connection errors in the container logs (not readable on the backend instance with the current rules), such as `Could not connect to any servers in your MongoDB Atlas cluster ... IP that isn't whitelisted`, `bad auth : Authentication failed` or `querySrv ENOTFOUND`. Exact wording depends on the driver version.

Checks and fixes:

| Check | Fix |
| --- | --- |
| Is the NAT Elastic IP in the Atlas network access list? Look it up with `aws ec2 describe-addresses --region ap-south-1 --filters "Name=tag:Name,Values=ecommerce-nat-eip" --query "Addresses[0].PublicIp" --output text` | Add `<nat-elastic-ip>/32` in Atlas. Atlas needs a short time to apply the change. |
| Does the base URI in the secret end with `/` and contain no query string? | Correct `MONGODB_BASE_URI` (deployment guide, section 6) |
| Are the user name and password right, and is the password URL-encoded? | Correct the value in Secrets Manager |
| Does the database user have access to `ecommerce_users`, `ecommerce_products`, `ecommerce_carts` and `ecommerce_orders`? | Grant read and write access in Atlas |
| Is the cluster running (not paused)? | Resume the cluster in Atlas |

The containers read the secret only when the backend instance first boots. After changing the secret, or after fixing an Atlas problem that kept services from starting, replace the instances so the services start with the corrected settings (deployment guide, section 17).

## 9. Secrets Manager Permissions and Missing Secret Values

The backend user-data script reads the secret `ecommerce/backend` with the instance role. If that fails, `set -eu` stops the script and no backend container is started.

| Message or symptom | Cause | Fix |
| --- | --- | --- |
| `AccessDeniedException ... is not authorized to perform: secretsmanager:GetSecretValue` | The instance profile is missing, the role policy does not cover this secret, or the secret is in another account or region | Check the `ecommerce-backend-role` policy and that the backend instance has `ecommerce-backend-profile` |
| `ResourceNotFoundException: Secrets Manager can't find the specified secret` | The secret does not exist in the region of the script (`var.aws_region`), or its name differs from `ecommerce/backend` | Create the secret in `ap-south-1` with that exact name |
| `terraform plan` fails while reading the secret | The data source cannot find `ecommerce/backend` | Create the secret before planning |
| `jq` prints an error and the script stops | The secret is not JSON, or `MONGODB_BASE_URI` or `JWT_SECRET` is missing (`jq -er` fails on a missing key) | Store the secret as JSON with exactly these two keys |
| The secret is encrypted with a customer-managed KMS key | The role also needs permission to decrypt with that key | Add `kms:Decrypt` for the key, or use the default AWS-managed key |

Check the key names without displaying any value:

```bash
aws secretsmanager get-secret-value --secret-id ecommerce/backend --region ap-south-1 \
  --query SecretString --output text | jq 'keys'
```

The expected output is `["JWT_SECRET", "MONGODB_BASE_URI"]`. Do not display or share the values. To change a value:

```bash
aws secretsmanager put-secret-value --secret-id ecommerce/backend --region ap-south-1 \
  --secret-string file://secret.json
```

Running containers keep the old values; replace the backend instance to apply the new ones.

## 10. Security Group and Route-Table Issues

| Symptom | Where to look |
| --- | --- |
| The browser times out on `http://<frontend-public-ip>` | The instance is running and has a public IP; `ecommerce-frontend-sg` allows TCP 80 from `0.0.0.0/0`; `ecommerce-public-rt` has `0.0.0.0/0` to `ecommerce-igw`; the URL starts with `http://`, not `https://` |
| Backend ports time out from the frontend instance | `ecommerce-backend-sg` allows TCP 3001 to 3004 with `ecommerce-frontend-sg` as the source; the backend instance uses `ecommerce-backend-sg` |
| Backend pulls, secret lookup or Atlas fail (timeouts) | `ecommerce-private-rt` has `0.0.0.0/0` to `ecommerce-nat-gateway`; the NAT Gateway is `available`, sits in the public subnet and has its Elastic IP; the backend security group allows outbound traffic |
| Everything worked, then stopped after console edits | Someone changed a rule by hand; `terraform plan` shows the drift |

Commands:

```bash
aws ec2 describe-route-tables --region ap-south-1 \
  --filters "Name=tag:Name,Values=ecommerce-private-rt" \
  --query "RouteTables[0].Routes"

aws ec2 describe-nat-gateways --region ap-south-1 \
  --filter "Name=tag:Name,Values=ecommerce-nat-gateway" \
  --query "NatGateways[].[NatGatewayId,State]" --output text

aws ec2 describe-security-groups --region ap-south-1 \
  --filters "Name=group-name,Values=ecommerce-backend-sg" \
  --query "SecurityGroups[0].IpPermissions"
```

## 11. SSH Timeouts

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `Connection timed out` | There is no inbound TCP 22 rule. The Terraform configuration does not define one. | Add a temporary rule for `<your-ip>/32` (deployment guide, section 15) |
| `Connection timed out` although the rule exists | Your public IP changed (new network or VPN), or a firewall blocks outbound port 22 | Check your address with `curl -s https://checkip.amazonaws.com` and update the rule |
| `Connection timed out` to a private address | You are using the private IP, or the backend instance, which has no public IP and no SSH path | Connect to the frontend instance's public IP; the backend cannot be reached over SSH |
| The address is wrong | The frontend public IP changed after a stop and start or a replacement | Read the current address with `terraform output -raw frontend_public_ip` |
| `Connection refused` | The instance is still booting, or the SSH service is not running | Wait for `2/2 checks passed` and retry |
| `Permission denied (publickey)` | Wrong key file or user name | Use the key pair named by `key_pair_name` and the user `ec2-user` |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | An address was reused by a replaced instance | `ssh-keygen -R <frontend-public-ip>` |

Use `ssh -v -i <path-to-key.pem> ec2-user@<frontend-public-ip>` to see where the connection stops.

## 12. PEM File Permission Errors Under WSL

**Symptom:** `WARNING: UNPROTECTED PRIVATE KEY FILE!`, `Permissions 0777 for '<file>.pem' are too open` or `bad permissions`.

**Cause:** files on a Windows drive (paths under `/mnt/c/...`) appear with open permissions inside WSL, and `chmod` has no effect on them. SSH refuses private keys that other users can read.

**Fix:** keep the key in the Linux file system:

```bash
mkdir -p ~/.ssh
cp /mnt/c/Users/<windows-user>/Downloads/<key-pair-name>.pem ~/.ssh/
chmod 400 ~/.ssh/<key-pair-name>.pem
ssh -i ~/.ssh/<key-pair-name>.pem ec2-user@<frontend-public-ip>
```

An alternative is to enable file permission metadata for Windows drives by adding `options = "metadata"` under `[automount]` in `/etc/wsl.conf` and restarting WSL with `wsl --shutdown`.

A `.pem` file is a private key. Do not commit it, do not paste it into chat or tickets, and delete copies you no longer need. The repository's `.gitignore` does not list `*.pem`, so keep key files outside the repository. If a key may have been exposed, create a new key pair and replace the instances.

## 13. Terraform Plans That Replace EC2 Instances

In a plan, a replacement appears as `-/+` (destroy and then create), with the attribute marked `# forces replacement`. The summary shows it as one resource to add and one to destroy. A replacement creates a new instance with a new ID and new IP addresses, and anything done by hand on the old instance is lost.

Behavior of the arguments used in this configuration:

| Change | Effect |
| --- | --- |
| `key_name` (`var.key_pair_name`) | Forces replacement. A key pair cannot be changed on a running instance. Commit `2fdc162` added it to both instances. |
| `ami`, from `data.aws_ami.amazon_linux` with `most_recent = true` | Forces replacement of both instances whenever a newer Amazon Linux 2 image matches the filter, even if you changed nothing |
| `subnet_id` | Forces replacement |
| `user_data` | With the provider defaults (`user_data_replace_on_change` is not set) the attribute is updated in place with a stop and start, and the new script does not run, because cloud-init runs user-data once per instance |
| `instance_type`, `iam_instance_profile`, `vpc_security_group_ids` | Updated in place |
| `security_groups` (used on the frontend instance) | The provider documentation recommends `vpc_security_group_ids` for instances in a VPC, which the backend instance uses. Read any plan that touches this argument closely. |

Chain reaction: if the backend instance is replaced, it gets a new private IP, and the frontend user-data embeds that IP. The frontend's `user_data` changes, but an in-place update does not recreate its container, so replace the frontend as well.

What to do:

1. Run `terraform plan` and read every `-/+` line and every `# forces replacement` note before applying.
2. If the replacement is intended (for example to run a corrected user-data script), apply it, or request it explicitly: `terraform apply -replace=aws_instance.backend -replace=aws_instance.frontend`.
3. If it is not intended, find the argument that changed. For an unexpected `ami` change, the usual cause is a newer image, and pinning the AMI ID in the configuration would stop it (not applied here).
4. After a replacement, read the new frontend address, wait for the user-data scripts, and repeat the validation checks.
5. The Atlas access list is unaffected, because the NAT Gateway and its Elastic IP are not replaced.

## 14. Inspecting Logs and Recovering Safely

1. **Preserve evidence first.** Before changing anything, copy the end of `/var/log/cloud-init-output.log`, the `docker ps -a` output and the console output of both instances. Remove secrets and tokens before saving them.
2. **Find the layer that fails.** Follow the path browser, Nginx, backend service, database:
   - Static page loads? If not, the frontend instance, the security group or the container (sections 1, 3, 4 and 10).
   - API call returns `502` or `504`? Nginx cannot reach the backend (sections 5 and 10).
   - API call returns `404`? Route problem (section 6).
   - API call returns `500` with a database message? Atlas (section 8).
   - No backend container at all? User-data, secrets or network (sections 3, 9 and 10).
3. **Fix at the smallest scope.** On the frontend instance you can repair a container by hand (section 4.4). The backend instance cannot be reached over SSH, so a backend fix means correcting the cause (secret, Atlas, Terraform) and replacing the instances (deployment guide, section 17).
4. **Prefer Terraform over manual edits.** Manual changes are drift and disappear on the next apply. Record any manual change, and remove temporary rules such as the SSH rule when finished.
5. **Protect the state.** State is a local `terraform.tfstate` file. Copy it before risky operations (`cp terraform.tfstate terraform.tfstate.backup`) and never commit it.
6. **Plan before you apply.** Read the plan (section 13) and avoid `-target` except for the Elastic IP step in the deployment guide.
7. **Re-validate.** After recovery, repeat the checks in [testing-and-validation.md](testing-and-validation.md).
8. **Handle exposed secrets.** If a secret value, token or key appears in a log, screenshot or chat, rotate it: change the Atlas password, generate a new JWT secret, update the secret with `put-secret-value`, and replace the backend instance.

## 15. Symptom Quick Reference

| Symptom | Likely cause | Section |
| --- | --- | --- |
| Browser times out on the frontend address | Security group, public route, stopped instance, `https://` used | 10 |
| Connection refused on port 80 | The frontend container is not running | 1, 3, 4 |
| Page loads, API calls fail with 502 | Backend not running, stale `BACKEND_PRIVATE_IP`, or blocked | 5, 10 |
| API call returns the React HTML page | The path did not match an Nginx location | 5 |
| `301` on an API path | Nginx trailing-slash redirect | 5 |
| `404 Cannot GET ...` | Wrong path, method or service | 6 |
| Product list is empty | No data in the database | 7 |
| `500` with `buffering timed out` | No Atlas connection | 8 |
| No backend containers after boot, or `AccessDeniedException` | Secret or IAM problem | 9 |
| Image pull errors | Name, tag, visibility, rate limit or no outbound route | 2 |
| SSH `Connection timed out` | No port 22 rule, changed IP, wrong address | 11 |
| `UNPROTECTED PRIVATE KEY FILE` | Key stored on a Windows drive under WSL | 12 |
| Plan wants to replace instances | `key_name`, new AMI, subnet or other forcing change | 13 |
