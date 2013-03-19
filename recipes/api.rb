#
# Cookbook Name:: cinder
# Recipe:: api
#
# Copyright 2012, Rackspace US, Inc.
# Copyright 2012, AT&T, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class ::Chef::Recipe
  include ::Openstack
end

platform_options = node["cinder"]["platform"]

platform_options["cinder_api_packages"].each do |pkg|
  package pkg do
    options platform_options["package_overrides"]

    action :upgrade
  end
end

directory ::File.dirname(node["cinder"]["api"]["auth"]["cache_dir"]) do
  owner node["cinder"]["user"]
  group node["cinder"]["group"]
  mode 00700

  only_if { node["openstack"]["auth"]["strategy"] == "pki" }
end

service "cinder-api" do
  service_name platform_options["cinder_api_service"]
  supports :status => true, :restart => true

  action :enable
end

db_user = node["cinder"]["db"]["username"]
db_pass = db_password "cinder"
sql_connection = db_uri("volume", db_user, db_pass)

rabbit_server_role = node["cinder"]["rabbit_server_chef_role"]
rabbit_info = config_by_role rabbit_server_role, "queue"

rabbit_user = node["cinder"]["rabbit"]["username"]
rabbit_pass = user_password "rabbit"
rabbit_vhost = node["cinder"]["rabbit"]["vhost"]

glance_api_role = node["cinder"]["glance_api_chef_role"]
glance = config_by_role glance_api_role, "glance"
glance_api_endpoint = endpoint "image-api"

identity_admin_endpoint = endpoint "identity-admin"
service_pass = service_password "cinder"

template "/etc/cinder/cinder.conf" do
  source "cinder.conf.erb"
  group  node["cinder"]["group"]
  owner  node["cinder"]["user"]
  mode   00644
  variables(
    :sql_connection => sql_connection,
    :rabbit_ipaddress => rabbit_info["host"],
    :rabbit_user => rabbit_user,
    :rabbit_password => rabbit_pass,
    :rabbit_port => rabbit_info["port"],
    :rabbit_virtual_host => rabbit_vhost,
    :glance_host => glance_api_endpoint.host,
    :glance_port => glance_api_endpoint.port
  )

  notifies :restart, "service[cinder-api]"
end

execute "cinder-manage db sync"

template "/etc/cinder/api-paste.ini" do
  source "api-paste.ini.erb"
  group  node["cinder"]["group"]
  owner  node["cinder"]["user"]
  mode   00644
  variables(
    :identity_admin_endpoint => identity_admin_endpoint,
    :service_pass => service_pass
  )

  notifies :restart, "service[cinder-api]", :immediately
end
