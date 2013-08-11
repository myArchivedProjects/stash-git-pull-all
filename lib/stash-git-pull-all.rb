#!/usr/bin/env ruby
# Use this script to retrieve every repository available in Stash
# on the first run, it will clone the repos into a defined directory
# following runs, it will perform a git pull over those repos
#
# INSTALL:
#
# yum install ImageMagick-devel
# yum install ImageMagick
# gem install bundler
# bundle install
#
# 
# USAGE:
#
# "Usage: <-u stash_username> <-p stash_password> <-gd gitrootdir> <-sh stash hostname> [-b branch/tag]"
#
require 'rubygems'
require 'bundler/setup'
require 'rest_client'
require 'json'
require 'fileutils'
require 'parallel'

@limit=1000
@tempdir=Dir.mktmpdir

if ARGV.count != 10
    puts "Usage: <-u stash_username> <-p stash_password> <-gd gitrootdir> <-sh stash hostname> [-b branch/tag]"
    exit 1
end

count=0
ARGV.each do |option|
    case option
    when "-h"
        puts "Usage: <-u stash_username> <-p stash_password> <-gd gitrootdir> <-sh stash hostname> [-b branch/tag]"
        puts "where (gitrootdir) is the base directory containing the git repositories"
        puts "where (stash hostname) is the fully qualified hostname for the Stash server"
        puts "where (stash_username) is a user with pull permissions on stash"
        puts "where (stash_password) is the password for that user"
        puts "where (branch/tag) is the branch or tag to checkout"
        exit 1
    when "-b"
        @checkout_branch=ARGV[count+1]
    when "-u"
        @my_user=ARGV[count+1]
    when "-p"
        @my_pass=ARGV[count+1]
    when "-gd"
        @my_git_rootdir=ARGV[count+1]
    when "-cd"
        @my_git_chefdir=ARGV[count+1]
    when "-sh"
        @my_stash=ARGV[count+1]
        @my_url="http://#{@my_stash}:7990/rest/api/1.0"
    end
    count=count+1
end

def get_collection(path)
    response = RestClient::Request.new(
        :method => :get,
        :url => @my_url + "/" + path.to_s + "?limit=#{@limit}",
        :user => @my_user,
        :password => @my_pass,
        :headers => { :accept => :json,
                    :content_type => :json }
    ).execute
   results = JSON.parse(response.to_str)
end

def clone_repo(item)
	filename="#{@tempdir}/#{item['project'].to_s + '_' + item['id']}"
	file = File.open(filename, "w")
        file.write("executing git clone on:  #{item['project'].to_s + '/' + item['id']} \n")
        file.write(%x[cd #{@my_git_rootdir + '/' + item['project'].to_s } ; git  clone -q  #{item['url'].to_s.gsub(@my_user,"#{@my_user}:#{@my_pass}")} #{item['id'].to_s } 2>&1])
        file.write("checking out branch #{@checkout_branch} on:  #{item['project'].to_s + '/' + item['id']} \n")
        file.write(%x[cd #{@my_git_rootdir + '/' + item['project'].to_s  + '/' + item['id']} ; git checkout -q #{@checkout_branch} 2>&1])
	file.close
	IO.foreach(filename) { |line| puts line }
end

def pull_repo(item)
	filename="#{@tempdir}/#{item['project'].to_s + '_' + item['id']}"
	file = File.open(filename, "w")
        file.write("executing git pull on:  #{item['project'].to_s + '/' + item['id']} \n")
        file.write(%x[cd #{@my_git_rootdir + '/' + item['project'].to_s + '/' + item['id']} ; git pull -q --all >> #{filename} 2>&1])
        file.write("checking out branch #{@checkout_branch} on:  #{item['project'].to_s + '/' + item['id']} \n")
        file.write(%x[cd #{@my_git_rootdir + '/' + item['project'].to_s  + '/' + item['id']} ; git checkout -q #{@checkout_branch} >> #{filename} 2>&1])
	file.close
	IO.foreach(filename) { |line| puts line }
end

#build list of projects
projects = Array.new
projects_json = get_collection("projects")
projects_json['values'].each  do |project|
    #p element['link']['url']
    projects  << project['key']  #projects contain: [CHEF,RUNDECK,SCRIPTS]
end

#build list of projects,gits,urls
list = Array.new
Parallel.each(projects, :in_threads => 50) do |project|
    repos_json = get_collection("projects/#{project}/repos")
    repos_json['values'].each do |element| #gitrepos: cookbook-apt ( name,cloneurl),cookbook-handler( name,cloneurl)
        list << {"project" => project,  "id" => element['name'], "url" => element['cloneUrl'] }
    end
end 

#create directory structure
Parallel.each(list, :in_threads => 50)  do |item|
        FileUtils.mkpath(@my_git_rootdir.to_s + '/' + item['project'].to_s + '/' + item['id'].to_s ) 
end

#git clone
Parallel.each(list, :in_threads => 50) do |item|
    #git clone the repo, if the git directory doesn't exist
    if (Dir.entries(@my_git_rootdir.to_s + '/' + item['project'].to_s + '/' + item['id'].to_s ) - %w{ . .. }).empty? 
        clone_repo(item)
    else
	    #do a git pull instead
	pull_repo(item)
    end
end


FileUtils.rm_rf(@tempdir)

