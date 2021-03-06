# LuxPower Inverter / Octopus Time-of-use Tariff Integration

This is a Ruby script to parse [Octopus ToU tariff](https://octopus.energy/agile/) prices and control a pair of [LuxPower ACS inverter](https://www.luxpowertek.com/ac-ess.html)s working in parallel in a master/ slave arangement according to rules you specify. Cleverly written by Chris Celsworth, I've never touched Ruby before as can be seen from my bad modifications :-)

The particular use-case of this is to charge your home batteries when prices are cheap, and use that power at peak times.

## Additional Parallel Inverter

These scripts have been slightly modifed to allow defining a Master/ Slave setup (not sure if we should be using that terminology nowadays - probably Primary/ Secondary would fit in better).

When a parallel setup is used, the two inverters currently favour one battery to discharge (they should really alternate between the two) to supply the load from the batteries. If the load increases, then both inverters take up the load. This is probably down the the limitation of how the primary (master) inverter can instruct the secondary (slave) inverter to adjust its output voltage to take its share of the load. This could be fixed via the firmware but it's currently not working.

However the advantage of using separate batteries on each inverter is that the charging current can be greatly increased. This is especially useful when there is a small cheap tariff window of an hour or so.

As a result of two inverters, the powers transmitted by the primary (master) inverter need to be summed up with those transmitted by the secondary (slave). This is something you currently need to do externally, say, within EmonPi during input processing.

## Installation

You'll need Ruby - at least 2.3 should be fine, which can be found in all good Linux distributions.

This apt-get command also installs the Ruby development headers and a compiler so Ruby can build extensions as part of installing dependencies:

```bash
sudo apt-get install ruby ruby-dev ruby-bundler git build-essential
```

Clone this repository to your machine:

```bash
git clone https://github.com/andywhittaker/octolux.git
cd octolux
```

Now install the gems. You may occasionally need to re-run this as I update the repository and bring in new dependencies or update existing ones. This will install gems to `./vendor/bundle`, and so should not need root:

```bash
bundle update
```

Create a `config.ini` using the `doc/config.ini.example` as a template:

```bash
cp doc/config.ini.example config.ini
```

This script needs to know information about both the master (primary) and slave (secondary) inverters.

* where to find your Lux inverter, host and port.
* mast is the master and slave is the, erm, slave.
* the serial numbers of your inverter and datalogger (the plug-in WiFi unit), which are normally printed on the sides.
* how many batteries you have, which determines the maximum charge rate (used in agile\_cheap\_slots rules)
* which Octopus tariff you're on, AGILE-18-02-21 is my current one for Octopus Agile.
* if you're using MQTT, where to find your MQTT server.

Copy `rules.rb` from the example as a starting point:

```bash
cp doc/rules.example.5p.rb rules.rb
```

The idea behind keeping the rules separate is you can edit it and be unaffected by any changes to the main script in the git repository (hopefully).

### Inverter Setup

Moved to a separate document, see [INVERTER\_SETUP.md](doc/INVERTER_SETUP.md).

## Usage

There are two components.

### server.rb

`server.rb` is a long-running process that we use for background work. In particular, it monitors the inverter for status packets (these include things like battery state-of-charge).

It starts a HTTP server which `octolux.rb` can then query to get realtime inverter data. It can also connect to MQTT and publish inverter information there. See [MQ.md](doc/MQ.md) for more information about this.

It's split like this because there's no way to ask the inverter for the current battery SOC. You just have to wait (up to two minutes) for it to tell you. The server will return the latest SOC on-demand via HTTP.

You can use the provided systemd unit file to run the server. The instructions below will start it immediately, and then automatically on reboot. You may need to edit `octolux_server.service` before copying it into place, unless your installation is in `/home/pi/octolux`. You'll need to be root to do these steps:

```bash
sudo cp systemd/octolux_server.service /etc/systemd/system
sudo systemctl start octolux_server.service
sudo systemctl enable octolux_server.service
```

The logs can then be seen with `journalctl -u octolux_server.service`.

### octolux.rb

`octolux.rb` is intended to be from cron, and enables or disables AC charging depending on the logic written in `rules.rb` (you'll need to copy/edit an example from docs/).

There's also a wrapper script, `octolux.sh`, which will divert output to a logfile (`octolux.log`), and also re-runs `octolux.rb` if it fails the first time (usually due to transient failures like the inverter not responding, which can occasionally happen). You'll want something like this in cron:

```bash
0,30 * * * * /home/pi/octolux/octolux.sh
```

To complement the wrapper script, there's a log rotation script which you can use like this:

```bash
59 23 * * * /home/pi/octolux/rotate.sh
```

This will move the current `octolux.log` into `logs/octolux.YYYYMMDD.log` at 23:59 each night.

## Development Notes

In your `rules.rb`, you have access to a few objects to do some heavy lifting.

<i>`octopus`</i> contains Octopus tariff price data. The most interesting method here is `price`:

* `octopus.price` \- the current tariff price\, in pence
* `octopus.prices` \- a Hash of tariff prices\, starting with the current price\. Keys are the start time of the price\, values are the prices in pence\.

<i>`lc`</i> is a LuxController, which can do the following:

* `lc.charge(true)` \- enable AC charging
* `lc.charge(false)` \- disable AC charging
* `lc.discharge(true)` \- enable forced discharge
* `lc.discharge(false)` \- disable forced discharge
* `lc.charge_pct` \- get AC charge power rate\, 0\-100%
* `lc.charge_pct = 50` \- set AC charge power rate to 50%
* `lc.discharge_pct` \- get discharge power rate\, 0\-100%
* `lc.discharge_pct = 50` \- set discharge power rate to 50%

Forced discharge may be useful if you're paid for export and you have a surplus of stored power when the export rate is high.

Setting the power rates is probably a bit of a niche requirement. Note that discharge rate is *all* discharging, not just forced discharge. This can be used to cap the power being produced by the inverter. Setting it to 0 will disable discharging, even if not charging.
