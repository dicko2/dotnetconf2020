# Url of github api
GITHUB_URL="https://api.github.com"
# or for GHE on-prem
# GITHUB_URL="https://github.mycompany.local/api/v3"

GITHUB_REG_URL=https://github.com/enterprises/mycompany
# or for GHE on-prem
# GITHUB_REG_URL="https://github.mycompany.local/enterprises/mycompany"
# these Url register a company wide runners, you can change them to the Url 
# of a git repo or an org to register runners at different levels

# replace below with the latest version
RUNNER_VER="2.275.1"

# replace below with a personal access token, better to pass via command line
GITHUB_PAT="00000"

# hard coded to github
username="github"
# replace this with a strong password, better to pass via command line
password="xxxx"

echo "==== Creating github user ===="
if grep -q "$username" /etc/passwd; then	
    echo "User $username does already exist.";
else
    echo "Adding user"
    adduser $username
    echo "$username:$password" | sudo chpasswd
    usermod -aG wheel $username
    sudoers_file=/etc/sudoers

    echo "updating sudoers file"
    echo "$username ALL=(ALL) NOPASSWD:ALL" >> $sudoers_file;
    opt='!requiretty'
    echo "Defaults:$username $opt" >> $sudoers_file;
    sudo usermod -aG docker $username
fi 

echo "Get token from github"
TOKEN_RESP=$(curl -X POST $GITHUB_URL/enterprises/agoda/actions/runners/registration-token \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GITHUB_PAT")

echo $TOKEN_RESP

GITHUB_TOKEN=$(echo $TOKEN_RESP | jq -r '.token')

echo "download and install github actions agent"
echo "============================================================================"
mkdir actions-runner && cd actions-runner

curl -O -L "https://github.com/actions/runner/releases/download/v$RUNNER_VER/actions-runner-linux-x64-$RUNNER_VER.tar.gz"
tar xzf "./actions-runner-linux-x64-$RUNNER_VER.tar.gz"
echo "download completed, changing permission on folder for docker group to have access"
chmod -R 774 /actions-runner
echo "starting runner config"
START_CMD='export http_proxy=http://my-proxy.local:8080 && export https_proxy=http://my-proxy.local:8080 && /actions-runner/config.sh --url GITHUB_REG_URL --token "GITHUB_TOKEN" --name $HOSTNAME --work "_work" --unattended --labels LABEL'
CMD3=${START_CMD/GITHUB_REG_URL/$GITHUB_REG_URL}
CMD2=${CMD3/GITHUB_TOKEN/$GITHUB_TOKEN}
CMD=${CMD2/LABEL/$LABEL}
su - github -c "$CMD"
echo "setup env vars for proxies"
cat << EOF > /actions-runner/.env
HTTP_PROXY=http://my-proxy.local:8080
HTTPS_PROXY=http://my-proxy.local:8080
NO_PROXY="*.local|*.other"
http_proxy=http://my-proxy.local:8080
https_proxy=http://my-proxy.local:8080
no_proxy="*.local|*.other"
EOF

echo "Setup Demon for github actions"
cat << EOF > /lib/systemd/system/github-actions.service
[Unit]
Description=Github-Actions-Agent
[Service]
WorkingDirectory=/actions-runner
ExecStart=/actions-runner/run.sh
Restart=always
RestartSec=10
User=root
Environment=RUNNER_ALLOW_RUNASROOT=1
[Install]
WantedBy=multi-user.target
EOF

sudo chmod 644 /lib/systemd/system/github-actions.service
sudo systemctl daemon-reload
sudo systemctl enable github-actions.service
echo "starting service"
sudo systemctl start github-actions.service
systemctl status github-actions.service
