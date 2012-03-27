#!/usr/bin/perl

# IMPORTANT NOTE:
# Make sure the cron user (or whoever running this) has permission
# to do an mdadm --detail on your raid device (default /dev/md0).

use warnings;
use strict;

use MIME::Lite;


# configuration
my $email   = 'nimbus@e7i.org';
my $subject = "RAID Array needs attention!";
my $file    = "/proc/mdstat";
my $raid    = "/dev/md0";
my $errors  = 0;



# check mdstat for strangities
my $mdadm_output;
open(MDSTAT, "<", $file);
while(<MDSTAT>) {
	if (m/\([Ff]\)/) {
		$errors = 1;
	}
	if (m/_/) {
		$errors = 1;
	}

	$mdadm_output .= $_;
}
close(MDSTAT);



# get mdadm --detail info
my $mdadm_detail = `/sbin/mdadm --detail $raid`;



# build the body of the email
my $body = qq(
<pre>

<h3>$file:</h3>
$mdadm_output


<h3>/sbin/mdadm --detail $raid:</h3>
$mdadm_detail

</pre>
);



# alert us if there are errors
if ($errors) {
	notify_via_email($email, $subject, $body);
}



# method for email notification
sub notify_via_email {
	my ($address, $subject, $body) = @_;

	my $msg = MIME::Lite->new(
		'From'        => '"RAID Problem!" <raid_problem@e7i.org>',
		'To'          => $address,
		'Subject'     => $subject,
		'Type'        => 'text/html',
		'Data'        => $body,
	);

	$msg->send();
}

