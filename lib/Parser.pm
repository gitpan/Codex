package Parser;
use strict;
use Command;

Command->newvar('text', '(?<! \S ) (.*)', sub { pop });
my @cmds = (
	Command->new('quit', 0, 'exit this shell'),
	Command->new('help', 0, 'show all commands'),
	Command->new('help $text', 0, 'show commands matching pattern')
);

sub new {
	my($proto, $obj, $cmds) = @_;
	bless {
		objs => [ $obj ],
		cmds => [ @cmds, @{ $cmds } ],
		pend => '',
		prompt => 'msh> ',
	}, ref($proto) || $proto;
}

sub newfile {
	my($proto, $obj, $cmds, $file, $prefix) = @_;
	require IO::File;
	my $fh = new IO::File $file;
	$obj->error("Can't open '$file': $!\n"), return unless $fh;
	$prefix = "" unless defined $prefix;
	bless {
		objs => [ $obj ],
		cmds => $cmds,
		pend => '',
		file => $fh,
		prefix => $prefix,
	}, ref($proto) || $proto;
}

sub cmds { shift->{'cmds'} }
sub prompt { shift->{'prompt'} }
sub quit { shift->{'quit'} = 1 }
sub quitted { shift->{'quit'} }
sub prefix { shift->{'prefix'} }

sub objs {
	my $self = shift;
	[ $self, @{ $self->{'objs'} || [] } ]
}

sub term {
	shift->{'term'} ||= do {
		require Term::ReadLine;
		Term::ReadLine->new('msh')
	};
}

sub pend {
	my $self = shift;
	return [ $self->{'pend'}, $self->{'pend'} = '' ]->[0];
}

# must let next() do the quit if we look ahead for multilines
sub readline {
	my $self = shift;
	if (exists $self->{'file'}) {
		my $fh = $self->{'file'};
		while (1) {
			my $line = <$fh>;
			last unless defined $line;
			next unless $line =~ /\S/;
			return $self->prefix . $line;
		}
		$self->quit, return unless defined $self->{'term'};
		delete $self->{'file'};
		# drop through
	}
	while (1) {
		my $text = $self->term->readline($self->prompt);
		$self->quit, return unless defined $text;
		return $text if $text =~ /\S/;
	}
}

sub help {
	my($self, $text) = @_;
	$text = '' unless defined $text;
	my @match = grep $_->cmd =~ /^$text/, @{ $self->cmds };
	if (@match) {
		print map { $_->cmd, ": ", $_->help, "\n" } @match;
	} else {
		print "No commands match '$text'\n";
	}
}

sub next {
	my $self = shift;
	my $cmd;
	my $text = $self->pend;
	$text = $self->readline unless length $text;
	unless (defined $text) {
		print "\n" if defined $self->{'term'};
		return;
	}
	($text, $self->{'pend'}) = split /\s*;\s*/, $text, 2;
	foreach (@{ $self->cmds }) {
		$cmd = $_->parse($self->objs, $text);
		next unless defined $cmd;
		my $meth = $cmd->method;
		$cmd->obj->$meth(@{ $cmd->args });
		return $self->quitted ? undef : 1;
	}
	$text = join ' ; ', grep length, $text, $self->pend;
	warn "Syntax error: $text\n";
	return 0;
}

1;
