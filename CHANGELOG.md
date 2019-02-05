# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [0.16.0] (In progress)

## [0.15.1] (2019-02-05)

### Added
- Add `unbind_queue` functionality to AMQP and Sandbox adapters (#31)

## [0.15.0] (2019-01-11)

### Added
- Add `delete_queue` functionality to AMQP and Sanddox adapters (#28)

### Fixed
- Fix incorrect example in `Freddy.Adapter.Sandbox` documentation (#26)

### Removed
- Remove `amqp` runtime dependency. Users must manually include this library
  into `mix.exs` if they still want to use it directly (#29, #30) 

## [0.14.0] (2018-07-17)

### Added
- `Freddy.RPC.Server` behaviour (#18)
- Support for connection to multiple hosts (#19)
- Support for exponential backoff intervals when re-establishing disrupted connection (#21)
- This changelog

### Changed
- `Freddy.RPC.Client` doesn't require response to have `%{success: true, output: result}` structure (c4b8aa3)
- Freddy now uses CircleCI to run tests (#20)
- Default connection options changed to have `[heartbeat: 10, connection_timeout: 5000]` options (ca44419)

### Deprecated
- `Freddy.Notifications.Listener` behaviour will be removed in 1.0
- `Freddy.Notifications.Broadcaster` behaviour will be removed in 1.0

### Fixed
- Fix crashing actors when connection couldn't be established in 5 seconds (ebc12c3)
- Fix `FunctionClauseError` in `Freddy.Consumer` in `handle_info/2` callback (#24)

## [0.13.1] - 2018-06-08

### Fixed
- Fix a bug when option `:durable` was ignored when declaring an exchange (a8b59b5)

## [0.13.0] - 2018-06-07

### Changed
- Freddy actors now communicate with broker through adapters layer

### Added
- Real AMQP adapter (#15)
- Sandbox adapter (#16)

## [0.12.1] - 2018-06-04

### Changed
- Improved documentation (#13)
- Allow specifying pre-request timeout in `Freddy.RPC.Client` (#14)

## [0.12.0] - 2018-06-01

### Added
- New callback `decode_message/3` to `Freddy.Consumer` behaviour
- New callback `encode_message/4` to `Freddy.Publisher` behaviour
- New callbacks `encode_request/2` and `decode_response/4` to `Freddy.RPC.Client` behaviour
- New configuration option `:consumer` to `Freddy.Consumer`
- `{:noreply, state, timeout}` as a possible return value of `Freddy.RPC.Client.handle_ready/2` callback
- `{:noreply, state, timeout}` as a possible return value of `Freddy.Consumer.handle_ready/2` callback
- `Freddy.Connection` as a replacement for `Freddy.Conn` module

### Changed
- Callback `handle_connected/1` in `Freddy.Consumer`, `Freddy.Publisher` and `Freddy.RPC.Client` now accepts
  two arguments - a connection meta-information and an internal state

### Removed
- Callback `Freddy.Consumer.handle_error/4` callback is removed
- Built-in logging from `Freddy.RPC.Client`. Users who need logging, need to implement it themselves in `on_response`,
  `on_timeout` and `on_return` callbacks
- Support for different adapters in `Freddy.Connection`
- Support for custom reconnection backoff intervals in `Freddy.Connection`
- `hare` dependency

### Fixed
- Fix a bug with crashing processes during reconnection

## [0.11.0] - 2018-05-12

### Added
- New callbacks `handle_connected/1` and `handle_disconnected/2` in `Freddy.Consumer`, `Freddy.Publisher`
  and `Freddy.RPC.Client` behaviours (#11)

## [0.10.2] - 2018-05-12

### Fixed
- Make default implementation of `Freddy.Consumer.handle_call/3` callback overridable (#10)

### Other
- Code is formatted with Elixir formatter

## [0.10.1] - 2017-08-29

### Changed
- Project dependencies are relaxed (#9)

## [0.10.0] - 2017-07-07

### Added
- `on_return/2` and `on_timeout/2` callbacks to `Freddy.RPC.Client` (#8)

### Changed
- `Freddy.RPC.Client.before_request/3` now accepts two arguments - a request structure and an internal state (#8)
- `Freddy.RPC.Client.on_response/3` now accepts request structure as a second argument
- `Freddy.RPC.Client` isn't bound to fixed routing key anymore (#8)

[0.16.0]: https://github.com/salemove/ex_freddy/compare/v0.15.1...master
[0.15.1]: https://github.com/salemove/ex_freddy/compare/v0.15.0...v0.15.1
[0.15.0]: https://github.com/salemove/ex_freddy/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/salemove/ex_freddy/compare/v0.13.1...v0.14.0
[0.13.1]: https://github.com/salemove/ex_freddy/compare/v0.13.0...v0.13.1
[0.13.0]: https://github.com/salemove/ex_freddy/compare/v0.12.1...v0.13.0
[0.12.1]: https://github.com/salemove/ex_freddy/compare/v0.12.0...v0.12.1
[0.12.0]: https://github.com/salemove/ex_freddy/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/salemove/ex_freddy/compare/v0.10.2...v0.11.0
[0.10.2]: https://github.com/salemove/ex_freddy/compare/v0.10.1...v0.10.2
[0.10.1]: https://github.com/salemove/ex_freddy/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/salemove/ex_freddy/compare/v0.9.2...v0.10.0
