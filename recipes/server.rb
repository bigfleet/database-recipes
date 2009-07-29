#
# Cookbook Name:: database
# Recipe:: default
#
# Copyright 2009, Jim Van Fleet
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# Two cases to prepare for:

# DB Node registers with Chef
# I log in, validate the node, instruct it "apply the database role to yourself"
# DB Node complies, setting a root password
# DB Node asks "any nodes have applications out there I need to configure myself for?"
# Server says "nope" seeing no nodes
# Run ends

# DB Node runs chef-client
# DB node asks "any nodes have applications out there I need to configure myself for?"
# Server, seeing node with <name-of-rails-app>, says "yes, this one"
# DB node generates appropriate user, database, and grants, flushing privileges.
# Run ends

include_recipe "mysql::server"

# Broadcast this as a database location.  If there are multiples, let client cookbooks
# sort it out.

node[:database] ||= Mash.new
node[:database][:location] = `hostname -f`.downcase.strip
 
Gem.clear_paths
require 'mysql'

Chef::Log.info "Assessing need for root DB user passwd change"

execute "mysql-root-privileges" do
  command "/usr/bin/mysql -u root -p#{node[:mysql][:server_root_password]} < /etc/mysql/root.sql"
  action :nothing
end

template "/etc/mysql/root.sql" do
  source "root.sql.erb"
  owner "root"
  group "root"
  mode "0600"
  notifies :run, resources(:execute => "mysql-root-privileges"), :immediately
end

# FIXME: narrow scope to requested databases, be agnostic about what they're for
Chef::Log.info "Fulfilling database requests"

requesting_nodes = search(:node, "database_requests:*")
requesting_nodes.select{ |rslt| rslt[:database][:requests] && !rslt[:database][:requests].empty? }.each do |array|
  # This hashifies the arrays we get, since we're not sure what the nested keys will be.
  hsh = {}
  array.each do |elt|
    compound_key = elt.first
    value = elt.last
    request_db, key = compound_key.split("_")
    hsh[request_db] ||= {}
    hsh[request_db][key] = value
  end
  Chef::Log.info "Database requests, in full: #{hsh.inspect}"
  hsh.each do |key, attrs|
    Chef::Log.info "Considering database for application: #{key}"
    db_name = key
    username = attrs["username"]
    password = attrs["password"]

    Chef::Log.info "Allowing database existence for application use: #{db_name}"
    execute "create #{db_name} database" do
      command "/usr/bin/mysqladmin -u root -p#{node[:mysql][:server_root_password]} create #{db_name}"
      not_if do
        m = Mysql.new("localhost", "root", node[:mysql][:server_root_password])
        m.list_dbs.include?(db_name)
      end
    end

    Chef::Log.info "Allowing database access for application use: #{db_name}"
    execute "mysql-app-privileges" do
      command "/usr/bin/mysql -u root -p#{node[:mysql][:server_root_password]} < /etc/mysql/#{db_name}-grants.sql"
      action :nothing
    end

    template "/etc/mysql/#{db_name}-grants.sql" do
      source "grants.sql.erb"
      owner "root"
      group "root"
      mode "0600"
      variables(
        :user     => username,
        :password => password,
        :database => db_name
      )
      notifies :run, resources(:execute => "mysql-app-privileges"), :immediately
    end 

  end 
end