#!/usr/bin/perl -T
use strict;
use Infoblox;
use Data::Dumper;
use Socket;
use Sys::Hostname;
require '/var/www/html/scripts/infoblox/infoblox_common.pl';

#right now, setting views globally
my $view_str = 'both';
my @views;
if ($view_str eq 'both') {
	@views = ('Internal','External');
} else {
	@views = ($view_str);
}

my $default_ttl = 300;


#declare list of changes based on locale
my %locations = (
	'sitey'	=> {
		'hu-ldap.harvard.edu'		=> {
			'ip'	=> '128.119.3.179',
			'type'	=> 'A',
			'ttl'	=> 300
		},
#		'ldap.pin1.harvard.edu'		=> {
#			'ip'	=> '128.119.3.183',
#			'type'	=> 'A',
#			'ttl'	=> 300
#		},
		'login.pin1.harvard.edu'	=> {
			'ip'	=> '128.119.3.190',
			'type'	=> 'A',
			'ttl'	=> 300
		},
#		'www.pin1.harvard.edu'		=> {
#			'ip'	=> '128.119.3.182',
#			'type'	=> 'A',
#			'ttl'	=> 300
#		},
		'fed.pin.harvard.edu'		=> {
			'ip'	=> '128.119.3.181',
			'type'	=> 'A',
			'ttl'	=> 300
		},
		'authzproxy.harvard.edu'	=> {
			'ip'	=> '128.119.3.177',
			'type'	=> 'A',
			'ttl'	=> 300
		}
	},



	'60ox'	=> {
		'hu-ldap.harvard.edu'		=> {
			'ip'	=> '128.103.149.45',
			'type'	=> 'A',
			'ttl'	=> 300
		},
#		'ldap.pin1.harvard.edu'		=> {
#			'ip'	=> '128.103.149.47',
#			'type'	=> 'A',
#			'ttl'	=> 300
#		},
		'login.pin1.harvard.edu'	=> {
			'ip'	=> '128.103.69.93',
			'type'	=> 'A',
			'ttl'	=> 300
		},
#		'www.pin1.harvard.edu'		=> {
#			'ip'	=> '128.103.149.47',
#			'type'	=> 'A',
#			'ttl'	=> 300
#		},
		'fed.pin.harvard.edu'		=> {
			'ip'	=> '128.103.69.84',
			'type'	=> 'A',
			'ttl'	=> 300
		},
		'authzproxy.harvard.edu'	=> {
			'ip'	=> '128.103.69.138',
			'type'	=> 'A',
			'ttl'	=> 300
		}
	}
);


#if the user didn't provide a valid flag for what direction to go in, complain and print
#help and die.
my $newhome = $ARGV[0];
$newhome =~ tr/A-Z/a-z/;
if (!$locations{$newhome}) {
	my @allhomes = keys %locations;
	my $allhomes = join('|', @allhomes);	

	print "This script is used to repoint PIN servers in case of outage/maintenance/etc.\n";
	print "USAGE: pincutover.pl [" . $allhomes . "]\n\n";
	exit;
}




#decide if we're using the prod or test appliance, based on which host we're on
my $host = hostname();
my $which_appliance = 'test';
if ($host =~ /^portal\.noc\b/gio) {
	$which_appliance = 'prod';
}






#announce what we're going to do, including which appliance (test or prod) and ask for conf
print "I'm about to carry out the following changes on the **" . $which_appliance . "** appliance:\n\n";
foreach my $name (sort keys %{ $locations{"$newhome"} }) {
	my $record_type = $locations{"$newhome"}{"$name"}{'type'};
	my $new_ip = $locations{"$newhome"}{"$name"}{'ip'};
	my $new_ttl = $default_ttl;
	if ($locations{"$newhome"}{"$name"}{'ttl'}) {
		$new_ttl = $locations{"$newhome"}{"$name"}{'ttl'};
	}
	print "\tsetting IP for " . $record_type . " " . $name . " to " . $new_ip . " with TTL of " . $new_ttl . "\n";
}
print "\n";
print "ok to continue? (y/n) .. ";
my $ok = <STDIN>;
chomp($ok);
$ok =~ tr/A-Z/a-z/;

if ($ok ne 'y') {
	print "\nexiting\n\n";
	exit;
}

print "\n";





#make it happen on all indicated views
my $conn = ibConnect($which_appliance);
#my @views = getViewObjects($view_str, $conn);

my @errors;

foreach my $name (sort keys %{ $locations{"$newhome"} }) {
	my $record_type = $locations{"$newhome"}{"$name"}{'type'};
	my $new_ip = $locations{"$newhome"}{"$name"}{'ip'};
	my $new_ttl = $default_ttl;
	if ($locations{"$newhome"}{"$name"}{'ttl'}) {
		$new_ttl = $locations{"$newhome"}{"$name"}{'ttl'};
	}
	
	my $lc_record_type = $record_type;
	$lc_record_type =~ tr/A-Z/a-z/;
	if ($lc_record_type eq 'host') {
		$record_type = 'Host';
	}
	
	my $obj_name = 'Infoblox::DNS::';
	if ($record_type ne 'Host') {
		$obj_name .= 'Record::';
	}
	$obj_name .= $record_type;
	
	foreach my $view (@views) {
		print " ** fetching record for " . $name . " in " . $view . " view .. ";
		
		my @records = $conn->get(
			'object'	=> $obj_name,
			'name'		=> $name,
			'view'		=> $view
		);
		
		if ($#records == -1) {
			print "!!! record not found!\n";
			push @errors, $name . " not found in " . $view . " view";
		}
		
		elsif ($#records == 0) {
			my $record = $records[0];
			
			#does the IP already match the request?
			if ($record->ipv4addr eq $new_ip) {
				print "!!! the record already has the ip address " . $new_ip . " in " . $view . " view\n";
				push @errors, $name . " already has the IP " . $new_ip . " not found in " . $view . " view";
			}
			
			#if no errors thrown, make the change
			else {
				$record->ipv4addr($new_ip);
				$record->ttl($new_ttl);
				my $response = $conn->modify($record);
				
				if ($response == 1) {
					print "done \n";
				} else {
					print "!! error trying to modify record (" . $conn->status_code() . ": " . $conn->status_detail . ")\n";
					push @errors, $name . " // " . $new_ip . " // " . $view . ": (" . $conn->status_code() . ": " . $conn->status_detail . ")";
				}
			}
		}
		
		else {
			print "!!! found more than one matching record in this view. skipping.\n";
			push @errors, "multiple matches found for " . $name . " in " . $view . " view";
		}
	}
}

print "\n\n";
if ($#errors > -1) {
	my $error_count = $#errors + 1;
	print $error_count . " errors were encountered. see above.";
} else {
	print "all requested changes made.";
}
print "\n\n";
