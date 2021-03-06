#!/usr/bin/perl

use FindBin qw($Bin);
use XML::DOM;
use Class::Struct;
use Encode;
use POSIX qw(strftime);
use LWP::Simple;
use Time::Local;
use DBI;

my $parser = new XML::DOM::Parser;

# User static settings
my $username = 'TedIrens';	# <= Put your username here
my $verbose = 0;		# <= set 1 to enable verbose output

my $cache_file = $Bin . "/pc/${username}_scrobbles.dat";

my $db_host = "localhost";
my $db_user = "root";
my $db_pass = "";
my $db_base = "search";
my $dsn = "dbi:mysql:$db_base:$db_host";

$dbh = DBI->connect($dsn, $db_user, $db_pass) || die "Can't connect to mysql!";
$dbh->do("SET NAMES 'utf8'");

# Script static variables
my $recent_tracks_url = 'http://ws.audioscrobbler.com/2.0/user/<USER>/recenttracks.xml?limit=200&page=<PAGE>';
my $version = 'v1.1 (09.03.2012)';

# Script dynamic variables
my %lastfm_track_playcount = ();
my %lastfm_track_playlast = ();

# statistic variables
my $processed_tracks = 0;
my $skipped_tracks = 0;

print "Copyright (c) 2012 Roman Gemini (roman_gemini\@ukr.net / woobind.org.ua)\n\n";
print "Debug messages : " . ($verbose ? "YES" : "NO") . "\n\n";

my $page = 1;
my $pages = 1;
my $scrobbles = 0;

# define variables
my $url;
my $total = 0;

my $rc_data;
my $rc_root;
my $rc_tracks;

my $track;
my $tag_title;
my $tag_artist;
my $tag_play_date;
my $last_date = 0;

my $recent_pos = 0;
my $last_pos = 0;
my $cache_pos = 0;
my $k;

my $cache_last_date = 0;
load_cache();
print "Processing XML data. This will take a while...\n";
P1: while(1) {

	$url = $recent_tracks_url;
	$url =~ s/<USER>/$username/g;
	$url =~ s/<PAGE>/$page/g;

	print "$url\n" if($verbose);

	eval { $rc_data = $parser->parsefile($url) };
	unless($rc_data) {
		print "Page $page contains errors!\n";
		if($page < $pages) { next; } else { last; }
	}

	$rc_root = $rc_data->getElementsByTagName("recenttracks");

	$pages     = $rc_root->item(0)->getAttribute("totalPages");
	$total     = $rc_root->item(0)->getAttribute("total");
	$rc_tracks = $rc_root->item(0)->getElementsByTagName("track");

	print "Parsing page $page of $pages\n";

	TRK: for my $j (0 .. $rc_tracks->getLength-1) {
		$track = $rc_tracks->item($j);
		next if ($track->getAttribute("nowplaying") eq "true");

		$tag_title = lc($track->getElementsByTagName("name")->item(0)->getFirstChild->getData());
		$tag_artist = lc($track->getElementsByTagName("artist")->item(0)->getFirstChild->getData());
		$tag_play_date = $track->getElementsByTagName("date")->item(0)->getAttribute("uts");

		$recent_pos = $total - (($page-1)*200+$j);
		printf "New scrobble: #%d: '%s' played at '%s'\n", $recent_pos, $tag_artist . " - " .$tag_title, timetostr($tag_play_date);
		$last_pos = $recent_pos if($recent_pos > $last_pos);
		last P1 if($recent_pos <= $cache_pos);

		if($lastfm_track_playlast{$tag_artist}{$tag_title} < $tag_play_date) {
			$lastfm_track_playlast{$tag_artist}{$tag_title} = $tag_play_date; 
		}

		$lastfm_track_playcount{$tag_artist}{$tag_title} ++;
		print "$tag_artist - $tag_title - " . timetostr($tag_play_date), "\n" if($verbose);

	}

	if($page >= $pages) {
		last;
	} else {
		$page ++;
	}

}

dump_cache();

print "Updating database...\n";
my $l_artists = 0;
my $l_tracks = 0;
my $l_plays = 0;
foreach my $k_artist (keys %lastfm_track_playcount) {
	$l_artists ++;
	for my $k_track (keys %{$lastfm_track_playcount{$k_artist}}) {
		$qr = $dbh->prepare("SELECT `index` FROM `search_files` WHERE (`audio_artist` LIKE " . $dbh->quote($k_artist) . ") AND (`audio_title` LIKE " . $dbh->quote($k_track) . ")");
		$qr->execute();
		while(@row = $qr->fetchrow_array()) {
			$dbh->do("INSERT INTO `jfs_file_stats` VALUES(${row[0]}, 1, 0, 1, 0) ON DUPLICATE KEY UPDATE `playcount` = '" . $lastfm_track_playcount{$k_artist}{$k_track} . "'");
		}
	}
}

$dbh->disconnect();

print "Press <ENTER> to exit...\n";
<>;



sub _866 { return encode("cp866", shift); }
sub timetostr {	return strftime("%d.%m.%Y %H:%M:%S", localtime(shift)); }
sub timetostrGM { return strftime("%d.%m.%Y %H:%M:%S", gmtime(shift)); }
sub strtotime {
	my $date = shift;
	my @d;
	# YYYY-MM-DD HH:MM:SS
	if(@d = $date =~ m/(\d{4})[-](\d{2})[-](\d{2})\s(\d{2})[:](\d{2})[:](\d{2})/) {	$d[1] --; return timelocal(@d[5,4,3,2,1,0]); }
	# DD.MM.YYYY H:MM:SS
	if(@d = $date =~ m/(\d{2})[\.](\d{2})[\.](\d{4})\s(\d{1,2})[:](\d{2})[:](\d{2})/) { $d[1] --; return timelocal(@d[5,4,3,0,1,2]); }
	# YYYY-MM-DD
	if(@d = $date =~ m/(\d{4})[-](\d{2})[-](\d{2})/) { $d[1] --; return timelocal(0, 0, 0, @d[2,1,0]); }
	return -1;
}

sub dump_cache() {
	print "Saving cache data...";
	my $header = 'myCache';
	my $stati = 0;
	open D, ">", $cache_file;
	binmode D, ":utf8";
	print D $header;
	print D pack "v", length($username);
	print D $username;
	print D pack "V", $last_pos;
	foreach my $arti (keys %lastfm_track_playcount) {
		foreach my $titl (keys %{$lastfm_track_playcount{$arti}}) {
			print D pack "v", length($arti);
			print D $arti;
			print D pack "v", length($titl);
			print D $titl;
			print D pack "v", $lastfm_track_playcount{$arti}{$titl};
			print D pack "V", $lastfm_track_playlast{$arti}{$titl};
			$stati += $lastfm_track_playcount{$arti}{$titl};
		}
	}
	close D;
	print "$stati scrobbles (marker at #$last_pos)\n";
}

sub load_cache() {
	print "Loading cache data...";
	my $header = 'myCache';
	my $ret = ''; my $len = 0;
	my $arti = ''; my $titl = '';
	my $stati = 0;

	open D, "<", $cache_file;
	binmode D, ":utf8";

	read D, $ret, length($header);
	if($ret ne 'myCache') { close D; return undef; }

	read D, $len, 2;
	$len = unpack "v", $len;
	read D, $ret, $len;
	if($ret ne $username) { close D; return undef; }

	read D, $len, 4;
	$cache_pos = unpack "V", $len;

	while(!eof(D)) {
		read D, $len, 2;
		$len = unpack "v", $len;
		read D, $arti, $len;

		read D, $len, 2;
		$len = unpack "v", $len;
		read D, $titl, $len;

		read D, $len, 2;
		$lastfm_track_playcount{$arti}{$titl} = unpack "v", $len;
		$stati += $lastfm_track_playcount{$arti}{$titl};

		read D, $len, 4;
		$lastfm_track_playlast{$arti}{$titl} = unpack "V", $len;
	}
	close D;
	print "$stati scrobbles (marker at #$cache_pos)\n";
}

