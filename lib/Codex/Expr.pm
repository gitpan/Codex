package Codex::Expr;
use strict;
use re 'eval';

my %done;
my $debug;

{
	package __RE;
	use strict;
	use re 'eval';
	use vars qw($re_num $re_var $re_fvar $re_bal $re_bbal);

	$re_num = qr/\d+/;
	$re_var = qr/\w[\w\d]*/;
	$re_fvar = qr{
		(
			(?p{ $__RE::re_var })
		)
		\(
			(
				(?p{ $__RE::re_bal })
				(?:
					\s* , \s* (?p{ $__RE::re_bal })
				)*
				\s*
			)
		\)
	}x;
	$re_bal = qr{
		(?:
			(?> [^()]+ )
		|
			\( (?p{ $__RE::re_bal }) \)
		)*
	}x;
	$re_bbal = qr{
		(?<! \w )
		\( ( (?p{ $__RE::re_bal }) ) \)
	}x;
}
sub re_num { $__RE::re_num }
sub re_var { $__RE::re_var }
sub re_bal { $__RE::re_bal }
sub re_bbal { $__RE::re_bbal }
sub re_fvar { $__RE::re_fvar }

sub new {
	my($proto, $codex, $text, $errors) = @_;
	if (exists $done{$text}) {
		warn "en: '$text' cached\n" if $debug;
		return $done{$text};
	}
	warn "en: trying '$text'\n" if $debug;
	my $e;
	my $newerrors = [];
	if ($text =~ /(?<!\w)\(/) {
		$e = $proto->new_complex($codex, $text, $newerrors);
	} else {
		$e = $proto->new_simple($codex, $text, $newerrors);
	}
	if ($e) {
		$e = $done{$e->text} ||= $e;
		splice @$errors;
	} elsif ($errors) {
		push @$errors, @$newerrors;
	} else {
		$codex->error($_) foreach @$newerrors;
	}
	$done{$text} = $e;
}

sub args { shift->{'args'} || [] }
sub type { shift->{'type'} }
sub atom { shift->type eq 'atom' }
sub value { shift->{'value'} }
sub op {
	shift->{'op'} || do {
		require Codex::Operator;
		Codex::Operator->builtin('null')
	};
}

sub debug {
	$debug = !$debug;
	%done = ();
}

sub new_simple {
	my($proto, $codex, $text, $errors) = @_;
	my($re_num, $re_var, $re_fvar) = (re_num(), re_var(), re_fvar());
	warn "ens: try simple '$text'\n" if $debug;
	my @args;
	if ($text =~ /^($re_num|$re_var)$/) {
		warn "ens: got atom ($1)\n" if $debug;
		return bless {
			type => 'atom',
			value => $1,
		}, ref($proto) || $proto;
	} elsif ($text =~ /^$re_fvar$/) {
		warn "ens: got function ($1)\n" if $debug;
		my $fvar = $1;
		my @textargs = split /\s*,\s*/, $2;
		while (@textargs) {
			my $t = shift @textargs;
			my $e = $proto->new($codex, $t, $errors);
			push(@args, $e), next if $e;
			$textargs[0] = "$e, $textargs[0]", next if @textargs;
			push @$errors, "Couldn't parse arguments '$t'";
			@args = ();
			goto operator;
		}
		my($func) = grep $_->name eq $fvar && @{ $_->vars } == @args,
				@{ $codex->functions };
		return bless {
			args => \@args,
			$func ? (
				type => 'op',
				op => $func,
			) : (
				type => 'atom',
				value => $fvar,
			),
		}, ref($proto) || $proto;
	}
	operator: foreach my $o (@{ $codex->operators }) {
		next unless @args = $text =~ $o->re;
		warn sprintf "ens: matched for %s, args: %s\n", $o->name,
				join ', ', map "'$_'", @args if $debug;
		foreach (@args) {
			my $e = $proto->new($codex, $_, $errors);
			if ($e) {
				$_ = $e;
			} else {
				warn "ens: failed after match for ", $o->name, "\n" if $debug;
				push @$errors, "Couldn't parse '$_'";
				next operator;
			}
		}
		warn "ens: success with ", $o->name, "\n" if $debug;
		return bless {
			'type' => 'op',
			'op' => $o,
			'args' => \@args,
		}, ref($proto) || $proto;
	}
	push @$errors, "Couldn't parse '$text'";
	return;
}

sub new_complex {
	my($proto, $codex, $text, $errors) = @_;
	my @z = ();
	my $re_bbal = re_bbal();
	while (1) {
		warn "enc: try for brackets in '$text'\n" if $debug;
		last unless $text =~ s/$re_bbal/"_z" . @z/ex;
		warn "enc: found subtext '$1'\n" if $debug;
		my $subtext = $1;
		my $e = $proto->new($codex, $subtext, $errors);
		if ($e) {
			warn "enc: succeeded for subtext '$subtext'\n" if $debug;
			push @z, $e;
		} else {
			warn "enc: failed for subtext '$subtext'\n" if $debug;
			push @$errors, "Couldn't parse subexpression '$subtext' in '$text'";
			return;
		}
	}
	unless (@z) {
		push @$errors, "Mismatched brackets in '$text'";
		return;
	}
	my $self = $proto->new($codex, $text, $errors);
	warn "enc: ", $self ? "succeeded" : "failed", " for '$text'\n" if $debug;
	$self && $self->transform(+{ map +("_z$_" => $z[$_]), 0 .. $#z });
}

sub text {
	my $self = shift;
	$self->{'text'} = $self->atom
			? @{$self->args}
				? sprintf("%s(%s)", $self->value,
						join ', ', map $_->text, @{ $self->args })
				: $self->value
			: $self->op->text($self->args)
		unless defined $self->{'text'};
	$self->{'text'};
}

sub construct {
	my($proto, $op, $args) = @_;
	my $self;
	if (ref $op) {
		$self = bless {
			type => 'op',
			op => $op,
			args => $args,
		}, ref($proto) || $proto;
	} else {
		$self = bless {
			type => 'atom',
			value => $op,
			args => $args,
		}, ref($proto) || $proto;
	}
	my $text = $self->text;
	warn "ec: constructed '$text'", $done{$text} ? " (cached)" : "", "\n"
		if $debug;
	$done{$text} ||= $self;
}

sub transform {
	my($self, $vars) = @_;
	my $diff = 0;
	return $vars->{$self->value} || $self unless @{ $self->args };
	my @args = map {
		my $t = $_->transform($vars);
		$diff = 1 if $t != $_;
		$t
	} @{ $self->args };
	if ($self->atom) {
		my @match = grep {
			(/^(.*?)\(.*\)$/ && $1 eq $self->value)
				? do {
					# this assumes fvar parms are all simple vars
					my $subvars = [ split /\s*,\s*/, $2 ];
					@$subvars == @{ $self->args }
						? [ $subvars, $vars->{$_} ]
						: +()
				} : +()
		} keys %$vars;
		last unless @match;
		die "Conflicting transformations for ".$self->value."()"
				if @match > 1;
		my($subvars, $match) = @{ $match[0] };
		die "Can't handle fvar(fvar) transforms" if grep /\(/, @$subvars;
		return $match->transform(+{ map {
			$subvars->[$_] => $self->args->[$_]
		} 0 .. $#$subvars });
	}
	return $self unless $diff;
	$self->construct($self->op, \@args);
}

sub vars {
	my $self = shift;
	$self->{'vars'} ||= do {
		my %a;
		$a{$1} = 1 if $self->atom && $self->value =~ /^(\w.*)$/;
		$a{$_} = 1 foreach map @{ $_->vars }, @{ $self->args };
		[ sort keys %a ];
	};
}

sub locate {
	my($self, $sub, $loc) = @_;
	unless (@$loc) {
		return [] if $self == $sub;
		$loc = [[-1]];
	}
	my($i) = @{ shift @$loc };
	if (@$loc) {
		my $next = $loc->[0][1]->locate($sub, $loc);
		return [ [ $i, $self ], @$next ] if $next;
	}
	while (++$i < @{ $self->args }) {
		my $kid = $self->args->[$i];
		my $next = $kid->locate($sub, []);
		return [ [ $i, $self ], @$next ] if $next;
	}
	return;
}

sub swap {
	my($self, $codex, $old, $new, $n) = @_;
	my($loc, $i) = ([], 0);
	for (; $i < $n; ++$i) {
		$loc = $self->locate($old, $loc) or last;
	}
	unless ($loc) {
		$codex->error("Swap: found only $i of $n copies of " . $old->text
				. " in " . $self->text) if $codex;
		return;
	}
	while (@$loc) {
		my($i, $kid) = @{ pop @$loc };
		$new = $self->construct($kid->op, [
			map $_ == $i ? $new : $kid->args->[$_], 0 .. $#{ $kid->args }
		]);
	}
	$new;
}

1;
