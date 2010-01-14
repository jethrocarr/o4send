#!/usr/bin/perl -w
#
#	o4send -> "Opensource Object Push Profile Sender"
#
#	Application for Linux which automatically sends files to compatible bluetooth
#	devices via OPP, ideal for marketing, conferences or promotions of any other
#	kind.
#
#	Please remember, this application is designed for people who want to
#	consent to recieving messages, don't modify it to spam people's phones
#	or send over-sided files to cause problems. That's just not cool. :-)
#
#	By default, o4send will only ever send a file once, regardless whether the phone
#	accepts it or not, that way if a user refuses, they won't keep getting nagged.
#
#
# 	Copyright (C) 2010 Amberdms Ltd
#
#	This program is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 3 of the License, or
#	(at your option) any later version.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#

use strict;

# Requires the following perl modules:
# * DBD::CSV
# * DBI
# * Text::CSV_XS
# * SQL::Statement;
#

use Digest::MD5;
use DBI;


#########################################################################
#									#
#				CONFIGURATION				#
#									#
#########################################################################


# configuration
my $location_file	= "test.txt";			# full path to file to send to bluetooth phone
my $location_csv	= "db/";			# location to store CSV database of MAC addresses
my $location_logfile	= "/dev/tty12";			# location of log file

my $debug		= 1;				# enable/disable debugging

# application paths
my $app_hcitool		= "/usr/bin/hcitool";		# hcitool for scanning for wifi
my $app_obexftp		= "/usr/bin/obexftp";		# tool for sending files to phone
my $app_sdptool		= "/usr/bin/sdptool";		# tool for fetching capabilities from phone




#########################################################################
#									#
#			APPLICATION FUNCTIONS				#
#									#
#########################################################################


#
# bt_phone_scan()
#
# Scans for nearby phones and returns array containing the MAC addresses
# of all found discoverable phones.
#
sub bt_phone_scan()
{
	log_add("debug", "executing bt_phone_scan");

	my @bt_phones;
	my @bt_iface;


	# make sure we have at least one device to be using
	#
	# TODO: expand this to scan for multiple devices and to only use ones
	# 	specified in configuration.
	#
	log_add("debug", "checking for existance of hci0 device...");
	open (APP, "$app_hcitool dev|") || die("unable to execute $app_hcitool");

	while (<APP>)
	{
		if (/hci0/)
		{
			# interface exists
			log_add("debug", "interface exists");

			push(@bt_iface, "hci0");

			last;
		}
	}

	close(APP);

	if (@bt_iface == 0)
	{
		log_add("debug", "no phones found");
		return 0;
	}


	# scan for phones
	# 
	# TODO: use the detected interfaces for this task
	#
	log_add("debug", "scanning for devices with hci0");

	open (APP, "$app_hcitool scan|") || die("unable to execute $app_hcitool");

	while (<APP>)
	{
		# find mac addresses and add them to list
		if (/\s([A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2}:[A-F0-9]{2})\s/)
		{
			log_add("debug", "phone with mac $1 found");

			push(@bt_phones, $1);
		}
	}
	

	return @bt_phones;

} # end of bt_phone_scan
	


#
# bt_phone_filesend ( filepath, phone_mac_address )
#
# Sends the provided file to the provided phone via Object Push Profile provided
# that the phone supports it.
#
# Return Codes:
# -2	Unknown Problem
# -1	Phone does not support OPP
#  0	Unable to contact phone or rejected transfer
#  1	Sent file successfully
#
sub bt_phone_filesend($$)
{
	log_add("debug", "Executing bt_phone_filesend");

	my $filename		= shift;
	my $bt_phone_mac	= shift;

	my $bt_opp_channel;


	# fetch phone capabilities and determine what channel (if any)
	# that OPP is listening on.
	
	log_add("debug", "Fetching phone capabilities and channel information");

	open (APP, "$app_sdptool browse $bt_phone_mac |") || die("unable to execute $app_sdptool");

	my $opp_block = 0;
	while (<APP>)
	{
		# Need to find the OPP section of the capabilities information
		#
		# TODO: needs testing with more phones, not sure if the strings returned
		#	are standardised or not.
		#
		# Some Nokia phones identify as:	"OBEX Object Push" (0x1105)
		#
		#

		if ($opp_block == 1)
		{
			# get channel then return
			if (/Channel: ([0-9]*)/)
			{
				$bt_opp_channel = $1;

				last;
			}
		}
		else
		{
			if (/"OBEX\sObject\sPush"\s\S0x1105\S/)
			{
				$opp_block = 1;
			}
		}
	}

	close(APP);


	if ($opp_block == 0)
	{
		log_add("debug", "Phone $bt_phone_mac does not appear to support OPP");
		return -1;
	}
	else
	{
		log_add("debug", "OPP supported, listening on channel $bt_opp_channel");
	}



	# now that we have the channel and mac, we can attempt to send the file by obexftp which
	# should return output like:
	#
	# we monitor the program output looking for Sending...... |done to make sure the file send
	# did complete, otherwise we fail with an error.
	#

	open (APP, "$app_obexftp --bluetooth $bt_phone_mac --channel $bt_opp_channel --nopath --noconn --uuid=none --put $filename 2>&1|") || die("unable to execute $app_obexftp");

	my $return = -2;

	while (<APP>)
	{
		# COMMON OUTPUTS
		#
		#
		# Suppressing FBS.
		# Connecting..\done
		# Tried to connect for 773ms
		# Sending "test.txt"...|done
		# Disconnecting../done
		#
		# Suppressing FBS.
		# Connecting...failed: connect
		# Tried to connect for 633ms
		# The user may have rejected the transfer: Connection refused
		#
		
		if (/^Sending[\S\s]*|done/)
		{
			log_add("info", "Sent file $filename to phone $bt_phone_mac successfully!");

			$return = 1;
			last;
		}

		if (/Connection\srefused/)
		{
			log_add("error", "Connection refused/rejected when contacting $bt_phone_mac");

			$return = 0;
			last;
		}
	}

	close(APP);


	if ($return == -2)
	{
		log_add("error", "An unknown problem occured when trying to transmit the file to phone $bt_phone_mac with obexftp");
	}

	return $return;

} # end of bt_phone_filesend




#########################################################################
#									#
#			SUPPORT FUNCTIONS				#
#									#
#########################################################################

# 
# log_add ( category[string], log_entry[string] )
#
# Prints logging message, usually used for debugging purposes
#
sub log_add($$)
{
	my $log_category = shift;
	my $log_entry = shift;

	# only display debugging log entries if debugging is enabled.
	if ($log_category eq "debug")
	{
		if ($debug == 0)
		{
			return 1;
		}
	}

	# if set, print copy of message to log file
	if ($location_logfile ne "")
	{
		open(LOG,">>$location_logfile") || print "Warning: Unable to write to log file!\n";
		print LOG "[$log_category] $log_entry\n";
		close(LOG);
	}

	print "[$log_category] $log_entry\n";

} # end of log_add


#
# file_checksum ( filename )
#
# returns a checksum of the provided file
#
sub file_checksum($)
{
	log_add("debug", "executing file_checksum");

	my $filename = shift;

	if (-e $filename)
	{
		open(FILE, $filename) or die "fatal error - unable to open $filename\n";

		# generate checksum by reading file
		my $ctx = Digest::MD5->new;
		$ctx->addfile(*FILE);
		my $checksum = $ctx->hexdigest;
		close(FILE);

		return $checksum;
	}
	else
	{
		log_add("error", "File $filename does not exist");
		die("fatal error");
	}

} # end of file_checksum



#########################################################################
#									#
#				MAIN LOOP				#
#									#
#########################################################################


# start of application
log_add("info", "Started openbluedistribute_srv");


# 1. Checksum the file.
my $checksum = file_checksum($location_file);



# 2. Connect to the phone database (and seed the DB if needed)

mkdir ($location_csv);
my $dbh = DBI->connect("DBI:CSV:f_dir=$location_csv") || die("Unable to connect to CSV database in $location_csv");

# if the CSV file doesn't exist, we need to create the table structure
if (! -e "$location_csv/phones_seen")
{
	$dbh->do("CREATE TABLE phones_seen (timestamp INTEGER, bt_phone_mac CHAR(17), transfer_filemd5sum CHAR(32), transfer_status CHAR(7))");
}




# 3. Scan for available phones

log_add("info", "Scanning for new phones...");


# return an array of all the phones that are discoverable
my @bt_phones = bt_phone_scan();

foreach my $bt_phone_mac (@bt_phones)
{
	# check if the current file has been sent to this device before
	my $sth = $dbh->prepare("SELECT timestamp FROM phones_seen WHERE bt_phone_mac='$bt_phone_mac' AND transfer_filemd5sum='$checksum' LIMIT 1");
	$sth->execute();
	$sth->fetchrow_array();

	if ($sth->rows == 0)
	{
		# TODO: should we explicity trying to send new files to devices that refused
		# 	or ignored them in the past?

		# connect to the bluetooth phone and send the file
		my $return = bt_phone_filesend($location_file, $bt_phone_mac);

		# add to DB records to prevent re-send
		if ($return == 1)
		{
			$dbh->do("INSERT INTO phones_seen (timestamp, bt_phone_mac, transfer_filemd5sum, transfer_status) VALUES (". time() .", '$bt_phone_mac', '$checksum', 'success')");
		}
		else
		{
			$dbh->do("INSERT INTO phones_seen (timestamp, bt_phone_mac, transfer_filemd5sum, transfer_status) VALUES (". time() .", '$bt_phone_mac', '$checksum', 'failure')");
		}

	}
	else
	{
		log_add("debug", "Phone $bt_phone_mac already has file with checksum $checksum, no need to re-send");
	}
}


# disconnect from DB
$dbh->disconnect();

# end of application loop
log_add("info", "Closing down openbluedistribute_srv");

exit 0;

