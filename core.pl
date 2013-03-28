=COPYLEFT
	Copyright 2004-2013, Patrick Bogen

	This file is part of Amygdale.

	Amygdale is free software; you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation; either version 2 of the License, or
	(at your option) any later version.

	Amygdale is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with Amygdale; if not, write to the Free Software
	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
=cut

use strict;
use POE;
require "irc.pl";
require "oscar.pl";
require "dcn.pl";

POE::Session->create(
	inline_states => {
		_start	=> \&on_start,
		receive	=> \&on_receive,
		receive_sysmsg => \&on_receive_sysmsg,
		receive_emote	=> \&on_receive_emote,
		receive_private	=> \&on_private,
		send_private	=> \&send_private,
		connect => \&do_connect,
	},
) or die( "Unable to create core POE session." );

sub on_start {
	my( $kernel, $heap ) = @_[KERNEL, HEAP];
	$kernel->refcount_increment(); #Keep the session around forever
	$kernel->alias_set( "core" );
	print( "CORE: Started.\n" );
	print( "CORE: ".$amygdale::config{ 'SERVERS' }."\n" );

	$heap->{ history } = [ ];

	my @servers = split( / /, $amygdale::config{ 'SERVERS' } );
	for my $server (@servers) {
		$kernel->yield( "connect", undef, $server, undef, undef );
	}
}

sub do_connect {
	my( $kernel, $heap, $nick, $server, $sid, $replypath ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2, ARG3 ];
	print( "CORE: Connect: $server\n" );
	my( $prot, $rest ) = split( /:\/\//, $server, 2 );
	my( $auth, $serv ) = split( /@/, $rest, 2 );
	my( $user, $pass ) = split( /:/, $auth, 2 );
	my( $host, $port ) = split( /:/, ( split( /\//, $serv, 2 ) )[0], 2 );
	my @opts = split( /\//, ( split( /\//, $serv, 2 ) )[1] );

	$user = amygdale::unescape( $user );
	$pass = amygdale::unescape( $pass );

	$prot =~ s/[^a-zA-Z]//;
	my $msg;
	if( $prot eq "irc" ) {
		$msg = "CORE: Starting IRC: $server";
		$heap->{ "list" } = [] unless exists $heap->{ "list" };
		push @{ $heap->{ "list" } }, [ $server, IRC::new( $kernel, $heap, $host, $port, $user, $pass, \@opts ) ];
	} elsif( $prot eq "dcn" ) {
		$msg = "CORE: Starting DCN: $server";
		$heap->{ "list" } = [] unless exists $heap->{ "list" };
		push @{ $heap->{ "list" } }, [ $server, dcn::new( $kernel, $heap, $host, $port, $user, $pass, \@opts ) ];
	} elsif( $prot eq "oscar" ) {
		$msg = "CORE: Starting OSCAR: $server";
		$heap->{ "list" } = [] unless exists $heap->{ "list" };
		push @{ $heap->{ "list" } }, [ $server, OSCAR::new( $kernel, $heap, $host, $port, $user, $pass, \@opts ) ];
	} else {
		$msg = "Invalid protocol: $prot";
	}
	if( defined( $sid ) && defined( $nick ) && defined( $replypath ) ) {
		$kernel->post( $sid, $replypath, $nick, $msg );
	} else {
		print( $msg, "\n" );
	}
}

sub on_private {
	my( $kernel, $heap, $nick, $msg, $sid ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];

	if( exists( $amygdale::ignored{ uc( $nick ) } ) ) {
		print "Private message from $nick dropped.\n";
		return;
	}

	my( $cmd, $rest ) = split( / /, $msg, 2 );
	$cmd = uc( $cmd );
	if( exists( $amygdale::commands{ $cmd } ) ) {
		&{ $amygdale::commands{ $cmd } }( $kernel, $heap, $nick, $rest, $sid, "send_private" );
	} else {
		$kernel->yield( "send_private", $nick, "Unknown command. Known commands:", $sid );
		$kernel->yield( "send_private", $nick, join( ", ", keys %amygdale::commands ), $sid );
	}
}

sub on_receive {
	my( $kernel, $heap, $nick, $msg, $sid ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
	my $tag;

	if( substr( $msg, 0, 1 ) eq "!" ) {
		print( "Secret message from $nick dropped.\n" );
		return;
	}

	if( exists( $amygdale::ignored{ uc( $nick ) } ) ) {
		print "Message from $nick dropped.\n";
		return;
	}

	if( exists( $amygdale::config{ taglen } ) ) {
		for my $self (@{ $heap->{ "list" } }) {
			if( $self->[1]->{ sid } == $sid ) {
				$tag = $self->[1]->{ tag };
			}
		}
		$tag = "[".$tag."]".(" "x($amygdale::config{ taglen } - length( $tag ) +1 ));
	} else {
		$tag = "";
	}

	for my $self (@{ $heap->{ "list" } }) {
		if( $self->[1]->{ sid } != $sid ) {
			$kernel->post( $self->[1]->{ ssid }, "send_public", "$tag<$nick> $msg", "$tag<$nick> " );
		}
	}

	push @{ $heap->{ history } }, "$tag<$nick> $msg";
	splice( @{ $heap->{ history } }, 0, -1*$amygdale::config{ 'HISTORY' } );
}

sub on_receive_emote {
	my( $kernel, $heap, $nick, $msg, $sid ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];

	my $tag;

	if( exists( $amygdale::ignored{ uc( $nick ) } ) ) {
		print "Message from $nick dropped.\n";
		return;
	}

	if( exists( $amygdale::config{ taglen } ) ) {
		for my $self (@{ $heap->{ "list" } }) {
			if( $self->[1]->{ sid } == $sid ) {
				$tag = $self->[1]->{ tag };
			}
		}
		$tag = "[".$tag."]".(" "x($amygdale::config{ taglen } - length( $tag ) +1 ));
	} else {
		$tag = "";
	}

	for my $self (@{ $heap->{ "list" } }) {
		if( $self->[1]->{ sid } != $sid ) {
			$kernel->post( $self->[1]->{ ssid }, "send_public", $tag."* $nick $msg", "$tag* " );
		}
	}
}

sub on_receive_sysmsg {
	my( $kernel, $heap, $msg, $sid ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];

	my $tag;

	if( exists( $amygdale::config{ taglen } ) ) {
		for my $self (@{ $heap->{ "list" } }) {
			if( $self->[1]->{ sid } == $sid ) {
				$tag = $self->[1]->{ tag };
			}
		}
		$tag = "[".$tag."]".(" "x($amygdale::config{ taglen } - length( $tag ) +1 ));
	} else {
		$tag = "";
	}

	for my $self (@{ $heap->{ "list" } }) {
		if( $self->[1]->{ sid } != $sid ) {
			$kernel->post( $self->[1]->{ ssid }, "send_public", $tag."$msg" );
		}
	}
}

sub send_private {
	my( $kernel, $heap, $who, $what, $sid ) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
	for my $self (@{ $heap->{ "list" } } ) {
		if( $self->[1]->{ sid } == $sid ) {
			$kernel->post( $self->[1]->{ ssid }, "send_private", $who, $what );
		}
	}
}
