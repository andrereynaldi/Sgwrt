'use strict';
'require view';
'require ui';
'require fs';

return view.extend({
    render: function() {
        return E([
            E('h2', _('Shutdown')),
            E('p',  _('Shutdown the device you are using')),
            E('hr'),
            E('button', {
                class: 'btn cbi-button cbi-button-negative',
                click: ui.createHandlerFn(this, 'handlePowerOff')
            }, _('Shutdown'))
        ]);   // <- ini yang hilang
    },       // <- ini juga penting untuk pisah render() dan handlePowerOff()

    handlePowerOff: function() {
        return ui.showModal(_('Shutdown Device'), [
            E('h4', {}, _('Shutdown the device you are using')),

            E('div', { class: 'right' }, [
                E('button', {
                    'class': 'btn btn-danger',
                    'style': 'background: red!important; border-color: red!important',
                    'click': ui.createHandlerFn(this, function() {
                        ui.hideModal();
                        ui.showModal(_('Processing...'), [
                            E('p', { 'class': 'spinning' }, _('The device may have powered off. If not, check manually.'))
                        ]);
                        return fs.exec('/sbin/poweroff').catch(function(e) {
                            ui.addNotification(null, E('p', e.message));
                        });
                    })
                }, _('OK')),
                ' ',
                E('button', {
                    'class': 'btn cbi-button cbi-button-apply',
                    'click': ui.hideModal
                }, _('Cancel'))
            ])
        ]);
    },

    handleSaveApply: null,
    handleSave: null,
    handleReset: null
});