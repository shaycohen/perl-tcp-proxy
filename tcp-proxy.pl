#!/usr/bin/perl
#
# Peteris Krumins (peter@catonmat.net)
# http://www.catonmat.net  --  good coders code, great reuse
#
# A simple TCP proxy that implements IP-based access control
# Currently the ports are hard-coded, and it proxies
# *** Modified; Staticly changed to: 0.0.0.0:43 -> whois.iana.org:43 *** 0.0.0.0:1080 to localhost:55555.
#
# Written for the article "Turn any Linux computer into SOCKS5
# proxy in one command," which can be read here:
#
# http://www.catonmat.net/blog/linux-socks5-proxy
#

use warnings;
use strict;
#use Data::Dumper;

use IO::Socket;
use IO::Select;

# Added flag to override allowed clients list
my $always_allow = 1;
my @allowed_ips = ('1.2.3.4', '5.6.7.8', '127.0.0.1', '192.168.1.2');
my $ioset = IO::Select->new;
my %socket_map;

my $debug = 1;

sub new_conn {
    my ($host, $port) = @_;
    return IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port
    ) || die "Unable to connect to $host:$port: $!";
}

sub new_server {
    my ($host, $port) = @_;
    my $server = IO::Socket::INET->new(
        LocalAddr => $host,
        LocalPort => $port,
        ReuseAddr => 1,
        Listen    => 100
    ) || die "Unable to listen on $host:$port: $!";
}

sub new_connection {
    my $server = shift;
    my $client = $server->accept;
    my $client_ip = client_ip($client);

    unless (client_allowed($client)) {
        print "Connection from $client_ip denied.\n" if $debug;
        $client->close;
        return;
    }
    print "Connection from $client_ip accepted.\n" if $debug;

    my $remote = new_conn('whois.ripe.net', 43);
    $ioset->add($client);
    $ioset->add($remote);

    $socket_map{$client} = $remote;
    $socket_map{$remote} = $client;
}

sub close_connection {
    my $client = shift;
    my $client_ip = client_ip($client);
    my $remote = $socket_map{$client};
    
    $ioset->remove($client);
    $ioset->remove($remote);

    delete $socket_map{$client};
    delete $socket_map{$remote};

    $client->close;
    $remote->close;

    print "Connection from $client_ip closed.\n" if $debug;
}

sub client_ip {
    my $client = shift;
    return inet_ntoa($client->sockaddr);
}

sub client_allowed {
    my $client = shift;
    my $client_ip = client_ip($client);
    return 1 if ($always_allow == 1);
    return grep { $_ eq $client_ip } @allowed_ips;
}

print "Starting a server on 0.0.0.0:43\n";
my $server = new_server('0.0.0.0', 43);
$ioset->add($server);

my $first_read;
my $last_write;
my $query_ip;
while (1) {
    for my $socket ($ioset->can_read) {
        if ($socket == $server) {
	    $first_read=0;
	    $last_write=0;
            new_connection($server);
        }
        else {
            next unless exists $socket_map{$socket};
            my $remote = $socket_map{$socket};
            my $buffer;
            my $read = $socket->sysread($buffer, 4096);
	    #print Dumper $read;
            if ( ($read) && ($last_write == 0) ) {
		if ($first_read == 0) { 
			$remote->syswrite($buffer);
			$query_ip=$buffer;
			$first_read=1;
		} else { 
			open RUN_WHOIS, "-|","whois $query_ip" or die "Could not execute local whois binary $!";
			while (<RUN_WHOIS>) { 
				$remote->syswrite($_);
			}
			$last_write=1;
		}
            } else {
                close_connection($socket);
            }
        }
    }
}

