/* This is free software, licensed under the Apache License, Version 2.0
 *
 * Copyright (C) 2024 Hilman Maulana <hilman0.0maulana@gmail.com>
 * Final version with all UI fixes, ready for source compilation.
 */

'use strict';
'require form';
'require rpc';
'require view';

const callServiceList = rpc.declare({
	object: 'service',
	method: 'list',
	params: ['name'],
	expect: { '': {} }
});

function getServiceStatus() {
	return L.resolveDefault(callServiceList('cloudflared'), {}).then(function (res) {
		var isRunning = false;
		try {
			isRunning = res['cloudflared']['instances']['cloudflared']['running'];
		} catch (ignored) {}
		return isRunning;
	});
}

return view.extend({
	load: function () {
		return Promise.all([
			getServiceStatus()
		]);
	},

	render: function (data) {
		let isRunning = data[0];
		let m, s, o;

		m = new form.Map('cloudflared', _('Cloudflare Tunnel'),
			_('Cloudflare Tunnel services help you get maximum security both from outside and within the network.') + '<br />' +
			_('Create and manage your network on the <a %s>Cloudflare Zero Trust</a> dashboard.')
				.format('href="https://one.dash.cloudflare.com" target="_blank"') + '<br />' +
			_('See <a %s>documentation</a>.')
				.format('href="https://openwrt.org/docs/guide-user/services/vpn/cloudfare_tunnel" target="_blank"')
		);

		s = m.section(form.NamedSection, 'config', 'cloudflared');

		o = s.option(form.DummyValue, '_status', _('Status'));
		o.rawhtml = true;
		o.cfgvalue = function(section_id) {
			var span = '<b><span style="color:%s">%s</span></b>';
			var renderHTML = isRunning ?
				String.format(span, 'green', _('Running')) :
				String.format(span, 'red', _('Not Running'));
			return renderHTML;
		};

		o = s.option(form.Flag, 'enabled', _('Enable'));
		o.rmempty = false;

		o = s.option(form.TextValue, 'token', _('Token'),
			_('The tunnel token is shown in the dashboard once you create a tunnel.')
		);
		o.optional = true;
		o.rmempty = false;
		o.monospace = true;
		o.password = true;

		// -- Tunnel Settings Section ---
		o = s.option(form.DummyValue, 'tunnel_settings_title', ''); // FIX: Set left-side label to empty string
		o.rawhtml = true;
		o.cfgvalue = function() { return '<h2>' + _('Tunnel Settings') + '</h2>'; };
		
		o = s.option(form.ListValue, 'protocol', _('Protocol'),
			_('Protocol used to connect to Cloudflare edge. QUIC is recommended for performance.')
		);
		o.value('auto', _('Auto'));
		o.value('http2', 'HTTP/2');
		o.value('quic', 'QUIC');
		o.default = 'auto';
		o.optional = true;

		o = s.option(form.Value, 'region', _('Region'),
			_('Connect to a specific Cloudflare region. Leave empty for automatic selection.')
		);
		o.placeholder = 'us-east-1';
		o.optional = true;

		o = s.option(form.Value, 'edge_bind_address', _('Edge Bind Address'),
			_('The local address to bind for connections to the Cloudflare edge.')
		);
		o.placeholder = '127.0.0.1';
		o.optional = true;
		
		o = s.option(form.ListValue, 'edge_ip_version', _('Edge IP Version'),
			_('The IP version to use for connecting to the Cloudflare edge.')
		);
		o.value('', _('auto'));
		o.value('4', _('ipv4-only'));
		o.value('6', _('ipv6-only'));
		o.default = '';
		o.optional = true;

		o = s.option(form.Value, 'retries', _('Connect Retries'),
			_('Maximum number of retries for connection failures.')
		);
		o.datatype = 'uinteger';
		o.placeholder = '5';
		o.optional = true;

		o = s.option(form.Value, 'grace_period', _('Grace Period'),
			_('Wait for this duration before shutting down the tunnel (e.g., 30s).')
		);
		o.placeholder = '30s';
		o.optional = true;

		o = s.option(form.Value, 'tag', _('Tags'),
			_('Key-value pairs for annotating the tunnel. Comma-separated (e.g., ENV=staging,TEAM=web).')
		);
		o.placeholder = 'KEY1=VALUE1,KEY2=VALUE2';
		o.optional = true;

		o = s.option(form.Value, 'metrics', _('Metrics Server Address'),
			_('Address to expose Prometheus metrics on (e.g., 127.0.0.1:9090).')
		);
		o.placeholder = '127.0.0.1:9090';
		o.optional = true;

		// -- Advanced / File Paths Section ---
		o = s.option(form.DummyValue, 'advanced_settings_title', ''); // FIX: Set left-side label to empty string
		o.rawhtml = true;
		o.cfgvalue = function() { return '<h2>' + _('Advanced Settings') + '</h2>'; };
		
		o = s.option(form.FileUpload, 'config', _('Custom config.yml path'),
			_('Path to a custom YAML configuration file. If used, the token and most other options here are ignored.') + '<br />' +
			_('See <a %s>documentation</a>.')
				.format('href="https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/configure-tunnels/local-management/configuration-file/" target="_blank"')
		);
		o.root_directory = '/etc/cloudflared/';
		o.optional = true;

		o = s.option(form.FileUpload, 'origincert', _('Origin Certificate path'),
			_('Path to the origin certificate for a named tunnel without a token.') + '<br />' +
			_('Obtain a certificate <a %s>here</a>.')
				.format('href="https://dash.cloudflare.com/argotunnel" target="_blank"')
		);
		o.root_directory = '/etc/cloudflared/';
		o.optional = true;

		// -- Logging Section ---
		o = s.option(form.DummyValue, 'logging_settings_title', ''); // FIX: Set left-side label to empty string
		o.rawhtml = true;
		o.cfgvalue = function() { return '<h2>' + _('Logging') + '</h2>'; };

		o = s.option(form.ListValue, 'loglevel', _('Log Level'));
		o.value('panic', _('Panic'));
		o.value('fatal', _('Fatal'));
		o.value('error', _('Error'));
		o.value('warn', _('Warn'));
		o.value('info', _('Info'));
		o.value('debug', _('Debug'));
		o.default = 'info';

		// SYNTAX FIX: This must be a new s.option, not a continuation of the previous 'o'
		o = s.option(form.Value, 'logfile', _('Log File Path'),
			_('Path to the log file. Leave empty to log to syslog.')
		);
		o.placeholder = '/var/log/cloudflared.log';
		o.optional = true;

		return m.render();
	}
});
