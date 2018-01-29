#!/usr/bin/env ruby

require "json"
require 'tempfile'
require 'set'

def inspect_image(image)
  puts("docker image inspect -f '{{.Size}}' #{image}")
  IO.popen(["docker", "image", "inspect", "-f", "{{.Size}}", image]) do |io|
    io.read.to_i
  end
end

def sh(cmd, *args)
  puts "$ #{cmd} " + args.map {|a| "'#{a}'" }.join(" ")
  system(cmd, *args)
end

LOG = "log-2.json"

def main(path)
  metadata ||= {"containers"=> {}}
  metadata = JSON.load(open(LOG, "r"))
  Dir.foreach(path) do |entry|
    container_data = {}

    report = File.join(path, entry, "artifacts", "creport.json")
    next unless File.exists?(report)
    data = JSON.load(open(report))

    files = Set.new()
    data["monitors"]["fan"]["process_files"].values.each do |process|
      files.merge(process.keys)
    end

    puts("docker inspect #{entry}")
    output = `docker inspect  -f '{{index .RepoTags 0}}' #{entry}`
    unless output =~ /^([^:]+):/
      next
    end
    tag = $1
    puts("tag: #{tag}")
    unless metadata["containers"][tag].nil?
      next
      #require 'pry'
      #binding.pry
    end

    whitelist = Tempfile.new('whitelist')
    files.each do |file|
      whitelist.write(file.gsub(/^\//, ""))
      whitelist.write("\0")
    end
    whitelist.close()

    puts "docker create #{entry}"
    container = IO.popen("docker create #{entry}").read.strip
    size = inspect_image(entry)

    container_data["size_before"] = size

    Dir.mktmpdir do |dir| 
      sh("docker export #{container} | tar -C #{dir} -x --null --files-from #{whitelist.path}")
      id = nil
      Dir.chdir dir do
        puts("tar -c . | docker import -")
        id = `tar -c . | docker import -`.strip
        container_data["size_after"] = inspect_image(id)
      end
      sh("docker rmi #{id}")
      sh("docker rm #{container}")
    end

    metadata["containers"][tag] = container_data
  end

  open(LOG, "w+") do |f|
    puts(LOG)
    f.puts JSON.pretty_generate(metadata)
  end
end

# directory of docker-slim report directory
# USAGE: $0 ~/go/bin/.images/
main(ARGV[0])
