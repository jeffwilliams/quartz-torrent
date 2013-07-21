#!/usr/bin/env ruby

TrackerPort = 8001
TrackedDfile = "dfile"

puts "Starting Tracker"
exec "bttrack --port #{TrackerPort} --dfile #{TrackedDfile}"

