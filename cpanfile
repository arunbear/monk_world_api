requires 'Devel::Assert', '1.06';
requires 'HTTP::Message', '7.01';
requires 'Mojo::Pg', '4.28';
requires 'Moo', '2.005005';
requires 'namespace::autoclean', '0.31';
requires 'Path::Iterator::Rule', '1.015';
requires 'Role::Tiny', '2.002004';
requires 'Type::Tiny', '2.008004';

on 'test' => sub {
  requires 'Test::Class::Most', '0.08';
  requires 'Test::Lib', '0.003';
  requires 'Sub::Override', '0.12';
};
