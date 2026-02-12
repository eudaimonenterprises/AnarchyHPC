#!/bin/bash

function add_message() {
  echo -e "$1" | fold -w70 -s >> /tmp/mesg.$$.dat
}

function show_message() {
  echo "+---------------------------------- X -------------------------------------+"
  echo "|                                                                          |"
  while read -r LINE
  do
    printf '|  %-70s  |\n' "$LINE"
  done < /tmp/mesg.$$.dat
  echo "|                                                                          |"
  echo "+--------------------------------------------------------------------------+"
  truncate -s0 /tmp/mesg.$$.dat
}

function count_down() {
  tel=$1
  while [ "$tel" -gt "0" ]; do
    echo -n "[$tel]  "
    sleep 1
    printf "\r"
    tel=$[tel-1]
  done
  echo
}

echo
add_message "Welcome to AnarchyHPC"
add_message "The system will now be prepared first..."
show_message
count_down 10
bash prepare.sh
cd site

if [ ! -f tui_configurator ]; then
    add_message "tui_configurator is missing. Please ensure it exists in site/."
    show_message
    exit 1
fi

# Automatically fix permissions
if [ ! -x tui_configurator ]; then
    chmod 755 tui_configurator
fi

./tui_configurator
TUI_RET=$?

if [ "$TUI_RET" != "0" ]; then
    add_message "The configuration TUI exited with an error."
    add_message "Please correct the problem and try again."
    show_message
    exit 1
fi

if [ ! "$(grep 'yml check' group_vars/all.yml)" ]; then
    grep 'yml check' group_vars/all.yml.example >> group_vars/all.yml
fi
cp hosts.example hosts
echo
add_message "Ansible Playbooks will now run"
show_message
count_down 5
ansible-playbook controller.yml compute-default.yml compute-ubuntu.yml
