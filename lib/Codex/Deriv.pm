package Codex::Deriv;
use strict;
use Codex::Operator;

my $builtin_equals = Codex::Operator->builtin('equals');

sub new {
	my($proto, $codex, $text) = @_;
	bless {
		'codex' => $codex,
		'text' => $text,
	}, ref($proto) || $proto;
}

sub text { shift->{'text'} }
sub codex { shift->{'codex'} }
sub error {
	my($self, $error) = @_;
	$error .= " in derivation '" . $self->text . "'";
	$self->codex->error($error);
}

sub data {
	my $self = shift;
	$self->{'data'} ||= do {
		my $t = [ split /,\s*/, $self->text ];
		@$t or return $self->error("Couldn't find anything");
		my $d = $self->parse($t, [ 'line' ]);
		if ($d && !$d->[0][0]->builtin) {
			shift @$d;
		} else {
			my $rule = $self->codex->lookup->{shift @$t}
				or return $self->error("Couldn't find a rule");
			$rule->builtin or return $self->error("Rule isn't a builtin");
			my $pat = $rule->do_builtin('args')
				or return $self->error("Couldn't get pattern for rule");
			$d = $self->parse($t, $pat)
				or return $self->error("Couldn't get expected args");
			[ $rule, $d ];
		}
	};
}

sub parse {
	my($self, $text, $pat) = @_;
	return [] if @$text == 0 && @$pat == 0;
	return if @$text < @$pat;
	return unless @$pat;
	my @pat = @$pat;
	my $curpat = shift @pat;
	if (@pat) {
		my($i, $j) = (0, @$text - @pat);
		while ($i++ < $j) {
			my $d = $self->parse([ @$text[0 .. $i - 1] ], [ $curpat ]);
			next unless $d;
			my $e = $self->parse([ @$text[$i .. $#$text] ], \@pat);
			next unless $e;
			return [ @$d, @$e ];
		}
		return;
	}
	$text = join ', ', @$text;
	if ($curpat eq 'number') {
		$text =~ /^(-?\d+)$/ or return;
		return [ $1 ];
	} elsif ($curpat eq 'expr') {
		my $e = Codex::Expr->new($self->codex, $text);
		return $e && [ $e ];
	} elsif ($curpat eq 'line') {
		my($line, $vars) = split /:/, $text, 2;
		return unless $line = $self->codex->lookup->{$line};
		return [ [ $line ] ] unless defined $vars;
		my @parts = split /,\s*/, $vars;
		my %vars;
		while (@parts) {
			my $part = shift @parts;
			return unless $part =~ s/^(\w+)=//;
			my $var = $1;
			my $e = Codex::Expr->new($self->codex, $part);
			$vars{$var} = $e, next if $e;
			return unless @parts;
			$parts[0] = "$var=$part, $parts[0]";
		}
		return [ [ $line, \%vars ] ];
	} else {
		die "panic: unexpected derivation type '$curpat'";
	}
}

sub cpderive {
	my($self, $left, $right) = @_;
	my($lsrc, $largs) = @$left;
	my($rsrc, $rargs) = @$right;
	foreach ($lsrc, $rsrc) {
		next if $_->builtin;
		next unless $self->{'line'};
		next if $self->codex->scope($self->{'line'}, $_, 1);
		$self->codex->error(sprintf "%s out of scope of CP %s", $_->lname, 
				$self->{'line'}->lname);
	}
	unless ($self->codex->scope($rsrc, $lsrc)) {
		$self->codex->error(sprintf "%s out of scope of %s for CP",
				$lsrc->lname, $rsrc->lname);
	}
	local $self->{'line'};
	($self->derive($left), $self->derive($right));
}

sub derive {
	my($self, $data) = @_;
	my($src, $args) = @$data;
	if ($src->builtin) {
		$src->do_builtin('derive', $self, $args);
	} else {
		if ($self->{'line'} && !$self->codex->scope($self->{'line'}, $src)) {
			$self->codex->error(sprintf "%s out of scope of %s", $src->lname,
					$self->{'line'}->lname);
		}
		if ($args) {
			$src->expr->transform($args);
		} else {
			 $src->expr;
		}
	}
}

sub test {
	my($self, $line) = @_;
	my $data = $self->data or return;
	local $self->{'line'} = $line;
	my $result = $self->derive($data);
	if (!$result) {
		$self->error("Couldn't derive anything");
	} elsif ($line->text ne $result->text) {
		$self->error(sprintf "Derivation '%s' yields '%s'",
				$line->text, $result->text);
	}
}

1;
