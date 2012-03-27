#!/usr/bin/perl

use strict;
use warnings;

use File::Copy;
use MIME::Lite;

# Config
my $remote_dir   = "/mnt/bittorrent";
my $unsorted_dir = $remote_dir;
my $music_dir    = "/space/Unsorted/Music";
my $movie_dir    = "/space/Unsorted/Movies";
my $tv_dir       = "/space/Unsorted/TV";
my $software_dir = "/space/Unsorted/Software";
my $verbose      = 0;
my $debug        = 0;


# First check the remote drive for max failure prevention
unless (-d $remote_dir and -r $remote_dir) {
	die ("Cannot read $remote_dir");
}

# Make sure we can read the Unsorted torrent dir
unless (-d $unsorted_dir and -r $unsorted_dir) {
	die ("Cannot read $unsorted_dir");
}


# Okay, now we'll look at all torrents in the Unsorted dir
opendir (UNSORTED, $unsorted_dir) || die "can't opendir $unsorted_dir: $!";
my @files = readdir(UNSORTED);
closedir(UNSORTED);


# Loop through them all and sync them!
my $synced_music     = '';
my $synced_movies    = '';
my $synced_tv        = '';
my $synced_software  = '';
my $not_synced_files = '';
my $not_synced_music = '';

foreach my $file (@files) {
	next if $file eq '.' or $file eq '..' or $file eq '.com.apple.timemachine.supported' or $file eq '.DS_Store';

	print("-- Found torrent: $unsorted_dir/$file\n") if $verbose;
	my $type = determine_torrent_type("$unsorted_dir/$file");
	print("   -- DETERMINED TYPE: $type\n") if $verbose;

	if ($debug) {
		print("Type y to do ($type) $file: ");
		my $in = <STDIN>;
		next if $in =~ m/n/;
		die unless $in =~ m/y/;
	}

	if ($type eq 'music') {
		# Only rsync if it wasn't marked as finished by caddie
		if (-e "$music_dir/$file/finished.txt") {
			$not_synced_music .= "$file<br>\n";
		} else {
			$synced_music .= "$file<br>\n";
			system("/usr/bin/rsync", "-r", "--update", "--modify-window=5", "$unsorted_dir/$file/", "$music_dir/$file");
		}
	}
	elsif ($type eq 'tv') {
		if (not -e "$tv_dir/$file") {
			$synced_tv .= "$file<br>\n";
		}
		system("/usr/bin/rsync", "-r", "--update", "--modify-window=5", "$unsorted_dir/$file", "$tv_dir");
	}
	elsif ($type eq 'software') {
		if (not -e "$software_dir/$file") {
			$synced_software .= "$file<br>\n";
		}
		system("/usr/bin/rsync", "-r", "--update", "--modify-window=5", "$unsorted_dir/$file", "$software_dir");
	}
	elsif ($type eq 'movie') {
		if (not -e "$movie_dir/$file") {
			$synced_movies .= "$file<br>\n";
		}
		system("/usr/bin/rsync", "-r", "--update", "--modify-window=5", "$unsorted_dir/$file", "$movie_dir");
	}
	else {
		$not_synced_files .= "($type) $file<br>\n";
	}
}


# Send me an email so I know I have stuff to sort
if ($not_synced_files ne '' or $synced_music ne '' or $synced_movies ne '' or $synced_software ne '' or $not_synced_music ne '') {
	my $body = '';

	if ($synced_music ne "") {
		$body .= "<br /><br />\n";
		$body .= "<h2>Unsorted Music:</h2>\n";
		$body .= "$synced_music\n\n";
	}

	if ($synced_movies ne "") {
		$body .= "<br /><br />\n";
		$body .= "<h2>Unsorted Movies:</h2>\n";
		$body .= "$synced_movies\n\n";
	}

	if ($synced_tv ne "") {
		$body .= "<br /><br />\n";
		$body .= "<h2>Unsorted TV:</h2>\n";
		$body .= "$synced_tv\n\n";
	}

	if ($synced_software ne "") {
		$body .= "<br /><br />\n";
		$body .= "<h2>Unsorted Software:</h2>\n";
		$body .= "$synced_software\n\n";
	}

	if ($not_synced_music ne "") {
		$body .= "<br /><br />\n";
		$body .= "<h2>Skipped Music (Already sorted):</h2>\n";
		$body .= "$not_synced_music\n\n";
	}

	if ($not_synced_files ne "") {
		$body .= "<br /><br />\n";
		$body .= "<h2>Not Synced Files:</h2>\n";
		$body .= "$not_synced_files\n\n";
	}

	notify_via_email('sortstuff@e7i.org', 'New Stuff to be Sorted', $body);
}


# Determines if a torrent is a movie or music
sub determine_torrent_type {
	my ($path) = @_;

	# If we were given a file, assume it is a movie
	if (-f $path) {
		my $type = determine_file_type("$path");
		return $type;
	}
	# If we were given a directory, look inside it
	elsif (-d $path) {
		# Check out the actual torrent dir name
		my $type = determine_file_type("$path");
		return $type if ($type ne 'unknown');

		opendir (TORRENT, $path) || die "can't opendir $path: $!";
		my @torrents = readdir(TORRENT);
		closedir(TORRENT);
	
		foreach my $torrent (@torrents) {
			next if $torrent eq '.' or $torrent eq '..';
			print("   - Determining $torrent\n") if $verbose;

			# If we found a file, try to detect the type, if we can't
			# figure it out skip to the next file; otherwise return the type
			if (-f "$path/$torrent") {
				my $type = determine_file_type("$torrent");
				next if ($type eq 'unknown');
				return $type;
			}
			# Most likely there will be another dir inside the torrent dir
			elsif (-d "$path/$torrent") {
				# Check out the actual torrent dir name
				my $type = determine_file_type("$path/$torrent");
				return $type if ($type ne 'unknown');

				opendir (TORRENT_SUBDIR, "$path/$torrent") || die "can't opendir $path/$torrent: $!";
				my @torrent_files = readdir(TORRENT_SUBDIR);
				closedir(TORRENT_SUBDIR);
			
				foreach my $file (@torrent_files) {
					next if $file eq '.' or $file eq '..';
					print("     - Determining $file\n") if $verbose;
			
					if (-f "$path/$torrent/$file") {
						my $type = determine_file_type("$path/$torrent/$file");
						next if ($type eq 'unknown');
						return $type;
					}
				}
			}
		}
		
		# If we haven't figured it out yet, it's unknown
		return 'unknown';
	}
}


# When passed a file name, determines the file type based on name
sub determine_file_type {
	my ($name) = @_;

	# Music file types
	if    ($name =~ m/\.mp3$/i)     { return "music"; }
	elsif ($name =~ m/\.ogg$/i)     { return "music"; }
	elsif ($name =~ m/\.m4a$/i)     { return "music"; }
	elsif ($name =~ m/\.flac$/i)    { return "music"; }
	# TV Episode file types
	elsif ($name =~ m/s\d\de\d\d/i) { return "tv"; }
	elsif ($name =~ m/hdtv/i)       { return "tv"; }
	# Don't copy HD content, we'll delete it later
	elsif ($name =~ m/1080p/i)      { return "hdcontent"; }
	elsif ($name =~ m/720p/i)       { return "hdcontent"; }
	elsif ($name =~ m/bluray/i)     { return "hdcontent"; }
	# Movie file types
	elsif ($name =~ m/\.avi$/i)     { return "movie"; }
	elsif ($name =~ m/\.mkv$/i)     { return "movie"; }
	elsif ($name =~ m/\.ogm$/i)     { return "movie"; }
	elsif ($name =~ m/\.mp4$/i)     { return "movie"; }
	elsif ($name =~ m/\.wmv$/i)     { return "movie"; }
	# Software file types
	elsif ($name =~ m/\.iso$/i)     { return "software"; }
	elsif ($name =~ m/\.dmg$/i)     { return "software"; }
	elsif ($name =~ m/\.exe$/i)     { return "software"; }
	else { return "unknown"; }
}


# Method for email notification
sub notify_via_email {
        my ($address, $subject, $body) = @_;

        my $msg = MIME::Lite->new(
                'From'        => '"Automatic Sorter" <auto_sorter@e7i.org>',
                'To'          => $address,
                'Subject'     => $subject,
                'Type'        => 'text/html',
                'Data'        => $body,
        );

        $msg->send();
}

