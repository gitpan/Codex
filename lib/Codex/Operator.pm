package Codex::Operator;
use strict;

my $re_expr = qr/(\S+(?:\s+\S+)*)/;
my %builtin = map +($_->[0] => __PACKAGE__->new(@$_)), (
	[ 'equals', ['a', 'b'], 'a = b' ],
	[ 'implies', ['a', 'b'], 'a => b' ],
	[ 'and', ['a', 'b'], 'a & b' ],
	[ 'not', ['a'], '~a' ],
	[ 'null', ['a'], 'a' ],
);

sub new {
	my($proto, $name, $vars, $pattern) = @_;
	my $self = bless {
		'name' => $name,
		'vars' => $vars,
		'pattern' => $pattern,
	}, ref($proto) || $proto;
	defined($self->re) or return undef;
	$self;
}

sub name { shift->{'name'} }
sub vars { shift->{'vars'} }
sub pattern { shift->{'pattern'} }
sub prec {
	my $self = shift;
	$self->{'prec'} = shift if @_;
	$self->{'prec'} || 0;
}

sub builtin {
	my($self, $name) = @_;
	defined($name) ? $builtin{$name} : exists($builtin{$self->name})
}

sub re {
	my $self = shift;
	$self->{'re'} ||= do {
		my $text = quotemeta $self->pattern;
		my $vars = join '|', @{ $self->vars };
		$text =~ s/((\\  )+)|(\b$vars\b)/$1 ? ' \s+ ' : $re_expr/eg;
		qr/^$text$/x;
	}
}

sub text {
	my($self, $args) = @_;
	my $text = $self->pattern;
	my $vars = join '|', map "($_)", @{ $self->vars };
	my $prec = $self->prec;
	# avoid method calls in s///e replacement by precalculation
	my @repl = map {
		($_->atom || $_->op->prec > $prec) ? $_->text : '(' . $_->text . ')'
	} @$args;
	unless (@$args == @{ $self->vars }) {
		die "Wrong number of args (".@$args.") for ".$self->name."\n";
	}
	$text =~ s/$vars/$repl[$#- - 1]/eg;
	$text;
}

1;
