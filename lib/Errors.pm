package Errors;
use strict;

sub errors { shift->{'errors'} ||= [] }
sub olderror { shift->{'olderror'} ||= [] }

sub error {
	my($self, $text) = @_;
	$text =~ s/($)\n?/
		defined($self->{'file'}) ? " at $self->{'file'}:$.\n" : "\n"
	/e;
	push @{ $self->errors }, $text;
	undef;
}

sub showerrors {
	my $self = shift;
	warn @{ $self->errors } if @{ $self->errors };
	splice @{ $self->errors };
}

sub pusherrors {
	my $self = shift;
	push @{ $self->olderror }, $self->errors if @{ $self->errors };
	splice @{ $self->errors };
}

sub poperrors {
	my $self = shift;
	push @{$self->errors}, @{ pop @{$self->olderror} } if @{$self->olderror};
}

sub clearerrors {
	my $self = shift;
	splice @{ $self->olderror };
}

1;
