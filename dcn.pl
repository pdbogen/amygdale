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

package dcn;

use POE qw( Wheel::SocketFactory Wheel::ReadWrite );
use warnings;
use strict;

our( %nicklist );

require "./locktokey.pl";

sub new {
	my( $kernel, $heap, $host, $port, $nick, $pass, $opts ) = @_;
	my @opts = @{ $opts };

	$nick = "" unless defined $nick;
	$host = "" unless defined $host;
	$port = 411 unless defined $port;
	
	print( "DCN : Started. $nick\@$host:$port\n" );
	my $self = {
		dcn		=> undef,
		share	=> 0,
		sid		=> undef,
		ssid	=> undef,
		server	=> $host,
		port	=> $port,
		nick	=> $nick,
		pass	=> $pass,
		tag		=> undef,
		debug	=> 0,
		delay	=> 1,
	};
	if( !( $self->{ 'port' } =~ /^[0-9]{1,5}$/ ) ) {
		$self->{ 'port' } = 411;
	}
	bless( $self );

	my $sess = POE::Session->create(
		inline_states => {
			_start		=> \&dcn_start,
			conn_fail	=> \&dcn_conn_fail,
			connected	=> \&dcn_connected,
			received	=> \&dcn_received,
			user_input	=> \&dcn_user_input,
			rawwrite	=> \&dcn_raw,
			send_public	=> \&dcn_privmsg,
			nicklist	=> \&dcn_nicklist,
			stop		=> \&dcn_stop,
		},
		heap => { "dcn" => $self },
	);
	$self->{ 'sid' } = $self->{ 'ssid' } = $sess->ID;

	for my $key (@opts) {
		my( $which, $what ) = split( /=/, $key, 2 );
		if( $which =~ /tag/i ) {
			$self->{ 'tag' } = amygdale::unescape( $what );
			my $foo = length( $self->{ 'tag' } );
			$amygdale::config{ 'taglen' } = $foo unless defined $amygdale::config{ 'taglen' };
			$amygdale::config{ 'taglen' } = $foo if $foo > $amygdale::config{ 'taglen' };
		}
		if( $which =~ /share/i ) {
			if( $what =~ /^[0-9]+$/ ) {
				$self->{ 'share' } = $what;
			} else {
				warn( "Misconfiguration: 'Share' of '$what' is invalid - non-numeric" );
			}
		}
		if( $which =~ /debug/i ) {
			$self->{ 'debug' } = 1;
		}
	}

	return $self;
}



# Translation hash, since DC protocl sucks
# Octal on the left, decimal DCN crap on the right

my %trm = (
	"0"	=> "/%%DCN000%%/",
	"5"	=> "/%%DCN005%%/",
	"24"	=> "/%%DCN036%%/",
	"60"	=> "/%%DCN096%%/",
	"7C"	=> "/%%DCN124%%/",
);

sub dcn_start {
	my ($kernel, $heap) = @_[KERNEL, HEAP];
	my $self = $_[HEAP]->{ 'dcn' };

	print( "DCN : Connecting to ".$self->{ 'server' }."\n" );
	if( exists( $heap->{ 'socket' } ) ) {
		delete $heap->{ 'socket' };
	}
	$heap->{ 'socket' } = POE::Wheel::SocketFactory->new( 
		RemoteAddress	=> $self->{ 'server' },
		RemotePort		=> $self->{ 'port' },
		SuccessEvent	=> 'connected',
		FailureEvent	=> 'conn_fail',
	);
};

sub dcn_connected {
	my ($kernel, $heap) = @_[KERNEL, HEAP];
	if( exists( $heap->{ 'readwrite' } ) ) {
		delete $heap->{ 'readwrite' };
	}
	$heap->{ 'readwrite' } = POE::Wheel::ReadWrite->new( 
		Handle		=> $_[ARG0],
		InputEvent	=> 'received',
		ErrorEvent	=> 'conn_fail',
		FlushedEvent=> undef,
		Filter		=> POE::Filter::Line->new( Literal => '|' ),
	);
	# This stores the status of when we connect.
	# Mostly so that we don't respond to extra crap
	# after we connect
	$heap->{ 'connected' } = 0;
	print( "DCN : Connected; waiting for data.\n" );
}

sub dcn_received {
	my ($kernel, $heap) = @_[ KERNEL, HEAP];
	my $line = $_[ARG0];
	$line =~ s/^ *//;
	my %noargs = (
		"\$GetPass" => 1,
		"\$GetNetInfo" => 1,
	);

	my( $cmd, $rest ) = split( / /, $line, 2 );
	if( $heap->{ 'dcn' }->{ 'debug' } == 1 ) {
		print( "DCD: $line\n" );
	}

	return 0 unless !( $line =~ /^[[:space:]]*$/ );
	if( !defined $cmd || ( !defined $rest && !exists( $noargs{ $cmd } ) ) ) {
		warn( "Malformed line, '$line'." );
		return;
	}
	# Refer to protocol documentation for info 
	# on most of what's below this line.
	if( $cmd =~ m/\$nicklist/i ) {
		$kernel->post( "dcn", "nicklist", $rest );
	} elsif( $heap->{ 'connected' } < 1 ) {
		if( $cmd =~ m/\$HubName/i ) {
			$heap->{ 'hubname' } = $rest;
			print( "DCN : Connected to $rest.\n" );
		} elsif( $cmd =~ m/\$Lock/i ) {
			my $key;
			# Split off the PK.
			($rest) = split( / /, $rest, 2 );
			$key = locktokey( $rest, 5 );
			print( "DCN : Authenticating.\n" );
			$heap->{ 'readwrite' }->put( "\$Key $key" );
			$heap->{ 'readwrite' }->put( "\$ValidateNick ".$heap->{ 'dcn' }->{ 'nick' } );
		} elsif( $cmd =~ m/^\$ValidateDenide/i ) {
			warn( "Nick is taken." );
		} elsif( $cmd =~ m/\$GetPass/i ) {
			print( "DCN : Logging in.\n" );
			if( !defined $heap->{ 'dcn' }->{ 'pass' } ) {
				warn( "Server requested a password but I have none configured." );
				return;
			}
			$heap->{ 'readwrite' }->put( "\$MyPass ".$heap->{ 'dcn' }->{ 'pass' } );
		} elsif( $cmd =~ m/\$BadPass/i ) {
			warn( "Bad password." );
			return;
		# The $connected thing is a bit of a hack. I'll need to work something out.
		# Incrementing $connected twice won't work, since sometimes we don't give a password.
		} elsif( $cmd =~ m/\$Hello/i ) {
			print( "Greeting server.\n" );
			$heap->{ 'readwrite' }->put( "\$Version 2.01" );
			$heap->{ 'readwrite' }->put( "\$MyINFO \$ALL ".$heap->{ 'dcn' }->{ 'nick' }." None <AMYGDALE V:0.2.x,M:P,H:1,S:3>\$ \$56Kbps1\$Octalthorpe's IRC-DC Gateway\$".$heap->{ 'dcn' }->{ 'share' }."\$" );
			$heap->{ 'readwrite' }->put( "\$GetNickList" );
			$heap->{ 'connected' }++;
		} elsif( $cmd =~ m/\$LogedIn/i ) {
			print( "Connection successful.\n" );
			$heap->{ 'dcn' }->{ 'delay' } = 1;
		}
	# Private messages are like '$To: Me From: You $ blah blah blah' or something.
	} elsif( $cmd eq "\$GetNetInfo" ) {
		print( "Sending \$NetInfo.\n" );
		$heap->{ 'readwrite' }->put( "\$NetInfo 0\$0\$P" );
	} elsif( $cmd =~ m/\$MyInfo/i ) {
		my @rest = split( / /, $rest );
		shift @rest;
		my $who = shift @rest;
		$nicklist{ $who } = 1;
	} elsif( $cmd =~ m/\$Quit/i ) {
		delete $nicklist{ $rest } unless !( exists $nicklist{ $rest } );
	} elsif( $cmd =~ m/^\$To:/i ) {
		my( $header, $body ) = split( /\$/, $rest, 2 );
		my( $to, $from ) = split( /From: /, $header, 2 );
		$from =~ s/ $//;
		$body =~ s/<.*> //;
		$body =~ s/&#36;/\$/g;
		$body =~ s/&#36;/|/g;
		print( "(DC ) [$from] $body\n" );
	# Public messages are like '<You> Blah blah blah|'
	} elsif( $cmd =~ m/^<.*/i ) {
		my $line;
		$cmd =~ s/(^<)|(>$)//g;
		$rest =~ s/&#36;/\$/g;
		$rest =~ s/&#124;/|/g;
		if( !( $cmd eq $heap->{ 'dcn' }->{ 'nick' } ) ) {
			if(	!( exists( $amygdale::ignored{ uc( $cmd ) } ) ) && 
				!( exists( $amygdale::config{ "DAMNDC" } ) ) ) {
				$rest =~ s/\x0A|\x0D/ /g;
				print( "(DC ) <$cmd> $rest\n" );
				while( length( $rest ) > 354 ) {
					$kernel->post( "core", "receive", $cmd, substr($rest, 0, 354), $_[HEAP]->{ 'dcn' }->{ 'sid' } );
					$rest = substr( $rest, 354 );
				}
				$kernel->post( "core", "receive", $cmd, $rest, $_[HEAP]->{ 'dcn' }->{ 'sid' } );
			} else {
				print( "(DC )*<$cmd> $rest\n" );
			}
		}
	# Ignore most everything coming from the server.
	} elsif( $cmd =~ m/(\$Quit|\$MyInfo|\$Hello|\$OpList|\$Lock|^ \*)/i ) {
	# Try to keep people from connecting to me
	} elsif( $cmd =~ m/^\$RevConnectToMe/i ) {
#		$heap->{ 'readwrite' }->put( "\$MaxedOut" );
	# The server appears to produce blank lines on occasion.
	} elsif( $cmd eq "*" ) {
		if( ! ( ( split( / /, $rest ) )[0] eq $heap->{ 'dcn' }->{ 'nick' } ) 
			&& !( exists( $amygdale::config{ "DAMNDC" } ) ) ){
			(my $nick, $rest ) = split( / /, $rest, 2 );
			print( "(DC ) * $nick $rest\n" );
			$kernel->post( "core", "receive_emote", $nick, $rest, $heap->{ 'dcn' }->{ 'sid' } );
		}
	} elsif( $cmd =~ m/\$Search/i) {
		my( $who, $rest ) = split( / /, $rest, 2 );
		my $pattern = ( split( /\?/, $rest, 5 ) )[4];
		if( $pattern eq "." ) {
			print( "Received a \$search for $pattern from $who." );
			print( " Bypassing.\n" );
			my $reply = "\$SR ".$heap->{ 'dcn' }->{ 'nick' }." .\05".
				"0 0/3\05".$heap->{ 'hubname' }." (".$heap->{ 'dcn' }->{ 'server' }.":".$heap->{ 'dcn' }->{ 'port' }.")\05".( split( /:/, $who, 2 ) )[1];
#			print( $reply, "\n" );
			$heap->{ 'readwrite' }->put( $reply );
		}
	} else {
		print( "FIXME: '$cmd -- $rest'\n" );
	}
}

sub dcn_conn_fail {
	print( "DCN: Connection failed: $_[ARG0]. Reconnecting in " );
	print( $_[HEAP]->{ 'dcn' }->{ 'delay' }, " seconds.\n" );
	$_[KERNEL]->delay( "_start", $_[HEAP]->{ 'dcn' }->{ 'delay' } );
	$_[HEAP]->{ 'dcn' }->{ 'delay' } *= 2;
	return;
}

sub dcn_privmsg {
	my( $kernel, $heap, $line ) = @_[ KERNEL, HEAP, ARG0 ];

	$line =~ s/\|/&#124;/g;
	$line =~ s/\$/&#36;/g;
	if( exists( $heap->{ 'readwrite' } ) ) {
		$heap->{ 'readwrite' }->put( "<".$heap->{ 'dcn' }->{ 'nick' }."> $line" );
	}
	return 0;
}

sub dcn_user_input {
	my ($kernel, $heap, $line) = @_[ KERNEL, HEAP, ARG0 ];
	return -1 unless exists $heap->{ 'readwrite' };
	$line =~ s/\|/&#124;/g;
	$line =~ s/\$/&#36;/g;
	if( exists( $heap->{ 'readwrite' } ) ) {
		$heap->{ 'readwrite' }->put( "<".$amygdale::config{ 'nick' }."> $line" );
	}
}

sub dcn_raw {
	my( $kernel, $heap, $line ) = @_[ KERNEL, HEAP, ARG0 ];
	return -1 unless exists $heap->{ 'readwrite' };
	$heap->{ 'readwrite' }->put( "$line" );
}

sub dcn_nicklist {
	my( $kernel, $heap, $rest ) = @_[ KERNEL, HEAP, ARG0 ];
	my @nicklist = split( /\$\$/, $rest );
	%nicklist = map( { $_ => 1 } @nicklist );
	print( "Nicklist: " );
	for my $i (keys %nicklist) {
		print( "$i " );
	}
	print( "\n" );
}

sub dcn_stop {
	my( $kernel, $heap ) = @_[ KERNEL, HEAP ];
	if( exists( $heap->{ 'socket' } ) ) {
		delete $heap->{ 'socket' };
	}
	if( exists( $heap->{ 'readwrite' } ) ) {
		delete $heap->{ 'readwrite' };
	}
	print( "DCN : Disconnected.\n" );
}
