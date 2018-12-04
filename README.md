# perl-Mirror-socks-proxy
A set of utility libraries to create/run SOCKS proxies, record and replay web traffic, and mock and modify content.

Requires the [Sugar](https://github.com/mirror12k/perl-Sugar-utility-library) and
[Iron](https://github.com/mirror12k/perl-Iron-networking-library) perl libraries
as well as openssl installed on the system (required for ssl intercepting).

Built on the Mirror::Server architecture which is an event-oriented, single-threaded io-selecting server architecture.
The Mirror::Server works with Mirror::SocketConnection objects and triggers events for them such as
on_connect, on_data, and on_disconnect. Connections can then trigger event callbacks on the parent server as they see fit.

[See the pod documentation for more info](Mirror/Server.pm)

## Mirror::Reflective
A basic SOCKS4/4a proxy server. Nothing fancy. Can be immediately started by running `perl Mirror/Reflective.pm`.

[See the pod documentation for more info](Mirror/Reflective.pm)

## Mirror::Enchanted
A complete HTTP/HTTPS intercepting SOCKS4/4a proxy. Can be immediately started by running `perl Mirror/Enchanted.pm`.
It buffers requests and responses, giving the opportunity for subclasses to validate/manipulate/reject them as needed.
The proxy decrypts ssl traffic with a root CA certificate which will need to be installed on the end client and
with the help of SSLCertificateFactory which generates fresh certificates for each domain.

[See the pod documentation for more info](Mirror/Enchanted.pm)

## Miror::Cursed
Extension of Mirror::Enchanted which heavily manipulates traffic.
Can be immediately started by running `perl Mirror/Cursed.pm my_config.json`.
A config file can be used to arbitrarily allow/block/mock/override any domain or wildcard domain.
It can even be used to inject content directly into pages.

[See the pod documentation for more info](Mirror/Cursed.pm)

## Miror::Crystalline
Extension of Mirror::Enchanted which records all http/https traffic to disk.
Can be immediately started by running `perl Mirror/Crystalline.pm`.
It records a single file of http messages in har-archive-like json format and stores content bodies in seperate files
to ease header searching.

[See the pod documentation for more info](Mirror/Crystalline.pm)

## Miror::Dreaming
Extension of Mirror::Enchanted which replays traffic as recorded by Mirror::Crystalline.
Can be immediately started by running `perl Mirror/Dreaming.pm`.
It plays back responses based on the url requested, which lets you test simple interactions without having to go to an external server for it.
Alternatively it can be set to play responses randomly for browser stress testing.

[See the pod documentation for more info](Mirror/Dreaming.pm)

## SSLCertificateFactory
This deserves a repo of its own.
After struggling for a long time to make a certificate which firefox will always accept,
I've come to the conclusion that this is no longer possible.
Instead I've been able to create a root certificate which is installed in firefox manually,
and then SSLCertificateFactory forces openssl to continually sign certificates for all necessary domains.
This solution is fast and require only one certificate to be installed on the end client.
See the recipe under [ssl_factory_config/build.sh](ssl_factory_config/build.sh) to build your own root certificate and end entity certificate signing request.
