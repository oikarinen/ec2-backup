#!/usr/bin/ruby
#

require 'date'
require 'rubygems'
require 'json'

# keep N backups for each volume
KEEP = 10

## volumes to backup with description
#BACKUP_VOLS = {
#	"vol-aabbccdd" => "some volume",
#	"vol-ccddeeff" => "other volume"
#	# add more volumes here
#}

require "./config.rb" # or reed above from a file

today = Date.today

string = `aws ec2 describe-snapshots`
allsnapshots = JSON.parse(string)

incomplete = {}
hastoday = {}
snapshots = {}

allsnapshots["Snapshots"].each do |s|
	if BACKUP_VOLS.has_key?(s["VolumeId"])
		dt = DateTime.parse(s["StartTime"])
		if dt >= today
			hastoday[s["VolumeId"]] = s["SnapshotId"]
		end
		if s["State"] != "completed"
			incomplete[s["VolumeId"]] = s["SnapshotId"]
		end
		if !snapshots.has_key?(s["VolumeId"])
			snapshots[s["VolumeId"]] = []
		end
		snapshots[s["VolumeId"]] << 
				{ "SnapshotId" => s["SnapshotId"], 
				"State" => s["State"], 
				"StartTime" => dt }
	end
end

BACKUP_VOLS.each do |vol, value|
	if !snapshots.has_key?(vol)
		snapshots[vol] = []
	end
end

puts "VOLUME\t\tSNAPSHOT\tSTATUS\t\tDATE\tDESC"
puts snapshots.sort.map{|vol, val| val.map{|s| vol + "\t" + 
	s["SnapshotId"] + "\t" + 
	s["State"] + "\t" + 
	s["StartTime"].strftime('%Y-%m-%d') + "\t" + 
	BACKUP_VOLS[vol]}}

puts "\nCREATING SNAPSHOTS"
snapshots.keys.each do |vol|
	if hastoday.has_key?(vol)
		puts vol + " has already snapshot for today: " + hastoday[vol]
	elsif incomplete.has_key?(vol)
		puts vol + " has pending snapshot: " + hastoday[vol]
	else
		puts "creating snapshot for " + vol
		system "aws ec2 create-snapshot --volume-id " + vol + " --description \"" + BACKUP_VOLS[vol] + "\""
	end
end

puts "\nDELETING OLD SNAPSHOTS"
snapshots.keys.each do |vol|
	if hastoday.has_key?(vol) or incomplete.has_key?(vol)
		#next
	end
	#puts vol, snapshots[vol]
	lambda{|x| x.nil? ? [] : x}.call(snapshots[vol].sort_by{|x| x.has_key?("StartTime") ? today : x["StartTime"]}.reverse[KEEP..-1]).each do |s|
		puts "deleting " + s["SnapshotId"] + " " + s["StartTime"].strftime('%Y-%m-%d') + " for " + vol
		puts "aws ec2 delete-snapshot --snapshot-id " + s["SnapshotId"]
	end
end
