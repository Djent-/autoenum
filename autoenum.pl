#!/usr/bin/perl
use strict;
use warnings;

# Check to see if Firefox is running
# Firefox cannot take headless screenshots
# if another Firefox window is already open
my $firefoxcount = `ps aux | grep firefox | wc -l`;
chomp $firefoxcount;
unless ($firefoxcount eq "2") {
	die "Please killall firefox before running autoenum: $firefoxcount";
}

# Command line argument is a file containing
# external IP addresses/ranges to scan,
# one per line
my $filename = shift;
my $DEBUG = 1;
my $ISLOCAL = 1; # Set to de-throttle masscan

open(FP, $filename) or die $!;
my @lines = <FP>;
close FP;

# Check there are no errors in the IPs
chomp @lines;
my $ips = @lines;
my $targets = join(" ", @lines);
unless ($targets =~ /^[0-9 .\/]*$/) {
	die("masscan can only take CIDR notation and IP addresses");
}

print "\033[1;31mWatch the masscan output in case the 'waiting' goes negative.\nYou will have to sudo pkill sudo to fix it.\n\033[0;0m";
# Execute masscan on the specified IPs and ranges
my $masscan = "sudo masscan $targets -p1-1000 --wait 0 --connection-timeout 2 -oG masscangrep.txt";
$masscan = "sudo masscan $targets -p1-65535 --rate 5000 --connection-timeout 2 -oG masscangrep.txt" unless $ISLOCAL;
#print "Masscan: $masscan\n";
my $output = `$masscan`;

# From the masscan output, grep for unique IP addresses
my $UniqueUpHosts = "cat masscangrep.txt | grep -o -E \"[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\" | sort -u | tee uniquehosts.txt";
$output = `$UniqueUpHosts`;
my @hosts = split("\n", $output);
my $UpHosts = join(",", @hosts);
my $hosts = @hosts;
print "UpHosts: $UpHosts\n" if $DEBUG;

# From the masscan output, grep for unique open ports
my $UniqueOpenPorts = "cat masscangrep.txt | grep -o -E \"([0-9]{2,5})/\" | sort -u  | sed \"s/\\///\" | tee uniqueports.txt";
$output = `$UniqueOpenPorts`;
my @ports = split("\n", $output);
my $OpenPorts = join(",", @ports);
my $ports = @ports;
print "OpenPorts: $OpenPorts\n" if $DEBUG;

# Execute nmap with various scripts
my $nmap = "nmap --script ssl-cert,ssl-enum-ciphers,rdp-enum-encryption -sV --max-scan-delay 10ms --max-rtt-timeout 60ms -p $OpenPorts $UpHosts -oN nmapnormal.txt -oX nmap.xml -oG nmapgrep.txt";
print "Nmap: $nmap\n" if $DEBUG;
my $nmapoutput = `$nmap`;

# Count up the ciphers in use by rating
my $ACiphers = `cat nmapnormal.txt | grep -E "\\s-\\sA\$" | sort -u | wc -l`;
my $BCiphers = `cat nmapnormal.txt | grep -E "\\s-\\sB\$" | sort -u | wc -l`;
my $CCiphers = `cat nmapnormal.txt | grep -E "\\s-\\sC\$" | sort -u | wc -l`;
my $DCiphers = `cat nmapnormal.txt | grep -E "\\s-\\sD\$" | sort -u | wc -l`;
my $ECiphers = `cat nmapnormal.txt | grep -E "\\s-\\sE\$" | sort -u | wc -l`;
my $FCiphers = `cat nmapnormal.txt | grep -E "\\s-\\sF\$" | sort -u | wc -l`;

# Find all the unique services running
my $UniqueServices = "cat nmapgrep.txt | grep -o -E \"Ports: .*\$\" | sed \"s/Ports: //g\" | sed \"s/, /\\n/g\" | cut -d/ -f 7 | awk 'NF' | sort -u | tee uniqueservices.txt";
my $TheServices = `$UniqueServices`;
my $services = `cat uniqueservices.txt | wc -l`;
print "Sort services: $UniqueServices\n" if $DEBUG;
print "Services: $TheServices" if $DEBUG;

# Look through the SSL certs in use for domain names
# You probably don't want this if the client is using shared hosting
my $SubjectAltNames = "cat nmapnormal.txt | grep -oE \"Subject Alternative Name: .*\$\" | cut -c 27- | sed 's/DNS:/\\n/g' | sed 's/, //g' | sed 's/\*.//' | sort -u | awk 'NF' | tee domainnames.txt";
my $TheDomains = `$SubjectAltNames`;
my $domains = `cat domainnames.txt | wc -l`;
print "SubjectAltNames: $SubjectAltNames\n" if $DEBUG;
print "Domains: $TheDomains" if $DEBUG;

# Do another check for Firefox processes
$firefoxcount = `ps aux | grep firefox | wc -l`;
chomp $firefoxcount;
unless ($firefoxcount eq "2") {
	die "Firefox cannot take headless screenshots while a Firefox window is open.";
}

# My makeshift EyeWitness
unless (-d "screenshots") {
	mkdir("screenshots", 0777);
}
unless (-d "harvester") {
	mkdir("harvester", 0777);
}
my @domains = split("\n", $TheDomains);
my $subdomains = 0;
my $TheSubDomains = "";
foreach my $domain (@domains) {
	my $firefox = "/usr/bin/firefox -screenshot $domain.png $domain && sleep 0.1 && mv $domain.png screenshots/";
	print "Firefox: $firefox\n" if $DEBUG;
	$output = `$firefox`;
	my $theharvester = "theHarvester.py -d $domain -b all -l 500 -f ./harvester/$domain";
	print "theHarvester: $theharvester\n" if $DEBUG;
	$output = `$theharvester`;
	# Rename the HTML file
	$output = `mv ./harvester/$domain ./harvester/$domain.html`;
	# theHarvester generates a ".xml" file for some reason
	# so we need to move it where it belongs
	$output = `mv .xml ./harvester/$domain.xml`;
	my $SubDomains = "cat ./harvester/$domain.xml | grep -oP \"<hostname>.*?</hostname>\" | grep \"$domain\" | tr '[:upper:]' '[:lower:]' | sort -u | perl -pe \"s/<\/?hostname>//g\"";
	print "SubDomains: $SubDomains\n" if $DEBUG;
	my @subdomains = split("\n", `$SubDomains`);
	$subdomains += @subdomains;
	$TheSubDomains .= join("\n", @subdomains);
	foreach my $subdomain (@subdomains) {
		$firefox = "/usr/bin/firefox -screenshot $subdomain.png $subdomain && sleep 0.1 && mv $subdomain.png screenshots/";
		print "Firefox: $firefox\n" if $DEBUG;
		$output = `$firefox`;
	}
}

# Gather screenshots from IPs with http services running.
# We can't screenshot IPs with ssl|http because their cert is probably
# only valid for the domain name and not the IP address.
# Firefox will refuse to screenshot pages with invalid certs.
my @webips = split("\n", `cat nmapgrep.txt | grep -oE "Host: [0-9\.]* .* [[:digit:]]*/open/tcp//http" | grep -oE "Host: [0-9\.]*" | cut -c 7- | tee httpips.txt`);
foreach my $ip (@webips) {
	# cat httpips.txt | grep $ip | grep -oE "[[:digit:]]*/open/tcp//http" | cut -d/ -f 1
	my @httpports = split("\n", `cat nmapgrep.txt | grep $ip | grep -oE "[[:digit:]]*/open/tcp//http" | cut -d/ -f 1`);
	foreach my $port (@httpports) {
		my $firefox = "/usr/bin/firefox -screenshot \"$ip($port).png\" $ip:$port && sleep 0.1 && mv \"$ip($port).png\" screenshots/";
		print "Firefox: $firefox\n" if $DEBUG;
		$output = `$firefox`;
	}
}

# Generate HTML report
my $now = localtime;
my $HTML = <<"END";
<html>
	<head><title>autoenum.pl Report $now</title></head>
	<body>
		<h1>autoenum.pl Report $now</h1>
		
		<h4>$ips IP Groups Enumerated ($hosts up)</h4>
		<pre>$targets</pre>
		
		<h4>$ports Unique Ports Open</h4>
		<p>$OpenPorts</p>
		
		<h4>$services Unique Services Up</h4>
		<pre>$TheServices</pre>
END

# Add the cipher ratings to the report
unless ($ACiphers + $BCiphers + $CCiphers + $DCiphers + $ECiphers + $FCiphers == 0) {
	$HTML .= "\t\t<h4>TLS/SSL Cipher Ratings</h4>";
	$HTML .= "<p>$ACiphers A-Rated Ciphers in Use</p>" unless $ACiphers + 0 == 0;
	$HTML .= "<p>$BCiphers B-Rated Ciphers in Use</p>" unless $BCiphers + 0 == 0;
	$HTML .= "<p>$CCiphers C-Rated Ciphers in Use</p>" unless $CCiphers + 0 == 0;
	$HTML .= "<p>$DCiphers D-Rated Ciphers in Use</p>" unless $DCiphers + 0 == 0;
	$HTML .= "<p>$ECiphers E-Rated Ciphers in Use</p>" unless $ECiphers + 0 == 0;
	$HTML .= "<p>$FCiphers F-Rated Ciphers in Use</p>" unless $FCiphers + 0 == 0;
}

$HTML .= <<"END";
		<h4>$domains Domain Names Enumerated ($subdomains Subdomains)</h4>
		<pre>$TheDomains</pre>
		<pre>$TheSubDomains</pre>
END

# Add each of the screenshots to the report
my @screenshots = <./screenshots/*>;
foreach my $screenshot (@screenshots) {
	my $source = substr($screenshot, 14, -4);
	$source =~ s/\((\d*)\)/:$1/;
	my $div = "\t\t<div>$source <img src=\"$screenshot\" style=\"max-width:500px;\"></div>\n<br>\n";
	$HTML .= $div;
}

my $nmappre = "\t\t<h4>nmap Output</h4>\n\t\t<pre>$nmapoutput</pre>";
$HTML .= $nmappre;

my $HTMLend = "\t</body>\n</html>";
$HTML .= $HTMLend;

open(FH, ">report.html") or die $!;
print FH $HTML;
close FH;
print "Created report.html\n";