package Command;
use strict;
use re 'eval';

my(%type, %allre);

sub new {
	my($proto, $cmd, $hist, $help) = @_;
	my $type = caller();
	my $self = bless {
		cmd => $cmd,
		hist => $hist,
		help => $help,
	}, ref($proto) || $proto;
	$type{$self} = $type;
	$self;
}

sub newvar {
	my($proto, $var, $re, $eval) = @_;
	my $type = caller();
	$allre{$type}{$var} = [ $re, $eval ];
}

sub hist { shift->{'hist'} }
sub args { shift->{'args'} }
sub vargs { shift->{'vargs'} }
sub text { shift->{'text'} }
sub cmd { shift->{'cmd'} }
sub obj { shift->{'obj'} }
sub type { $type{+shift} }
sub help { shift->{'help'} }

sub method {
	my $self = shift;
	$self->{'method'} ||= [ map {
		s/\s*\$.*//;
		s/\s+//g;
		$_;
	} $self->cmd ]->[0];
}

sub re {
	my $self = shift;
	$self->{'re'} ||= do {
		my $text = quotemeta $self->cmd;
		my $type = $self->type;
		$self->{'vargs'} = [];
		$text =~ s/(\\ )+/ \\s+ /g;
		$text =~ s/(^|\s+)(\w+)(\s+|$)/$1(?i:$2)$3/g;
		$text =~ s/\\\$/\$/g;
		$text = join '', map {
			/^\$(\w+)$/ ? do {
				my $x = $allre{$type}{substr $_, 1}
						or die "Couldn't parse $_ in $text\n";
				push @{ $self->vargs }, $x->[1];
				$x->[0]
			} : $_
		} split /(\$\w+)/, $text;
		qr/(^ \s* $text \s* $)/x;
	};
}

sub parse {
	my($self, $objs, $text) = @_;
	my(@args) = ($text =~ $self->re) or return;
	shift @args;
	unless (@args == @{ $self->vargs }) {
		warn $self->cmd, ": expect " . @{$self->vargs} . ", got "
				. @args . " args for /" . $self->re . "/x\n";
		return;
	}
	my $type = $self->type;
	my $obj = [ grep ref($_) eq $type, @$objs ]->[0];
	$obj->pusherrors if $obj->can('pusherrors');	# cache this
	unless (defined $obj) {
		$obj->poperrors if $obj->can('poperrors');	# do
		return;
	}
	my(@vargs) = map {
		&{ $self->vargs->[$_] }($obj, $args[$_])
	} 0 .. $#args;
	if (grep !defined, @vargs) {
		$obj->poperrors if $obj->can('poperrors');  # do
		return;
	}
	$obj->clearerrors if $obj->can('clearerrors');	# and again
	bless {
		%$self,
		method => $self->method,
		args => \@vargs,
		text => $text,
		obj => $obj,
	}, ref $self;
}

1;
