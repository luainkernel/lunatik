/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

(function () {
	var root = document.documentElement;
	var base = document.body.getAttribute('data-root') || '';

	function stored(key) { try { return localStorage.getItem(key); } catch (e) { return null; } }
	function store(key, value) { try { localStorage.setItem(key, value); } catch (e) { } }

	var themeButton = document.getElementById('theme');
	if (themeButton) themeButton.addEventListener('click', function () {
		var dark = root.getAttribute('data-theme') === 'dark' ||
			(!root.hasAttribute('data-theme') && matchMedia('(prefers-color-scheme: dark)').matches);
		var theme = dark ? 'light' : 'dark';
		root.setAttribute('data-theme', theme);
		store('lunatik-theme', theme);
	});

	var navButton = document.getElementById('nav');
	if (navButton) navButton.addEventListener('click', function () {
		var open = document.body.classList.toggle('nav-open');
		navButton.setAttribute('aria-expanded', open ? 'true' : 'false');
	});

	var content = document.querySelector('.content');
	if (!content) return;

	/* headings get an anchor the reader can copy */
	var headings = content.querySelectorAll('h2[id], h3[id]');
	headings.forEach(function (h) {
		var a = document.createElement('a');
		a.className = 'anchor';
		a.href = '#' + h.id;
		a.setAttribute('aria-label', 'Link to this section');
		a.textContent = '#';
		h.insertBefore(a, h.firstChild);
	});

	/* code blocks: a light highlight where LDoc gave none, and a copy button */
	var LUA = /\b(and|break|do|else|elseif|end|false|for|function|goto|if|in|local|nil|not|or|repeat|return|then|true|until|while)\b/g;
	var COMMENT = {
		lua: /^--\[\[[\s\S]*?\]\]|^--[^\n]*/,
		c: /^\/\*[\s\S]*?\*\/|^\/\/[^\n]*/,
		shell: /^#(?=\s|$)[^\n]*/,
	};
	function language(text) {
		if (/^\s*(local |function |return |end$)|require\(/m.test(text)) return 'lua';
		if (/^\s*#include|^\s*(static|struct|int|void) /m.test(text)) return 'c';
		return 'shell';
	}
	function highlight(code, lang) {
		var text = code.textContent, out = '', i = 0;
		var rules = [
			[COMMENT[lang], 'tok-c'],
			[/^"(?:[^"\\\n]|\\.)*"|^'(?:[^'\\\n]|\\.)*'|^\[\[[\s\S]*?\]\]/, 'tok-s'],
			[/^\b0x[0-9a-fA-F]+\b|^\b\d+\b/, 'tok-n'],
		];
		function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
		while (i < text.length) {
			var rest = text.slice(i), hit = null;
			var bol = i === 0 || /\s/.test(text[i - 1]);
			for (var r = 0; r < rules.length && !hit; r++) {
				if (r === 0 && lang !== 'lua' && !bol) continue; /* a comment starts a word, a URL's // does not */
				var m = rest.match(rules[r][0]);
				if (m) hit = [m[0], rules[r][1]];
			}
			if (hit) { out += '<span class="' + hit[1] + '">' + esc(hit[0]) + '</span>'; i += hit[0].length; continue; }
			var word = rest.match(/^[A-Za-z_]\w*/);
			if (word) {
				out += lang === 'lua' && LUA.test(word[0]) ? '<span class="tok-k">' + word[0] + '</span>' : word[0];
				LUA.lastIndex = 0;
				i += word[0].length;
				continue;
			}
			out += esc(text[i]);
			i++;
		}
		code.innerHTML = out;
	}
	content.querySelectorAll('pre').forEach(function (pre) {
		var code = pre.querySelector('code') || pre;
		var lang = pre.classList.contains('example') ? 'lua' : language(code.textContent);
		pre.setAttribute('data-lang', lang);
		/* LDoc colours every fenced block as Lua; a shell or C block is coloured again from its text */
		if (!(lang === 'lua' && pre.querySelector('span'))) highlight(code, lang);
		var text = code.innerText;
		var button = document.createElement('button');
		button.className = 'copy';
		button.type = 'button';
		button.textContent = 'Copy';
		button.addEventListener('click', function () {
			var done = function () { button.textContent = 'Copied'; setTimeout(function () { button.textContent = 'Copy'; }, 1500); };
			if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, function () { });
		});
		pre.appendChild(button);
	});

	/* on this page, with the section in view marked */
	var toc = document.getElementById('toc');
	if (toc && headings.length > 1) {
		var list = document.createElement('ul');
		var links = {};
		headings.forEach(function (h) {
			var li = document.createElement('li');
			if (h.tagName === 'H3') li.className = 'toc-sub';
			var a = document.createElement('a');
			a.href = '#' + h.id;
			a.textContent = h.textContent.replace(/^#/, '');
			li.appendChild(a);
			list.appendChild(li);
			links[h.id] = a;
		});
		toc.appendChild(list);
		if ('IntersectionObserver' in window) {
			var current = null;
			var observer = new IntersectionObserver(function (entries) {
				entries.forEach(function (e) {
					if (!e.isIntersecting) return;
					if (current) current.classList.remove('active');
					current = links[e.target.id];
					if (current) current.classList.add('active');
				});
			}, { rootMargin: '-15% 0px -70% 0px' });
			headings.forEach(function (h) { observer.observe(h); });
		}
	} else if (toc) {
		toc.parentNode.removeChild(toc);
	}

	/* search over the index search.js holds */
	var input = document.getElementById('q'), results = document.getElementById('results');
	if (!input || !results || !window.LUNATIK_SEARCH) return;
	var index = window.LUNATIK_SEARCH, selected = -1;
	function render(q) {
		q = q.trim().toLowerCase();
		results.innerHTML = '';
		selected = -1;
		if (!q) { results.hidden = true; return; }
		var hits = [];
		for (var i = 0; i < index.length && hits.length < 40; i++) {
			var e = index[i], name = e[0].toLowerCase(), score = name.indexOf(q);
			if (score < 0 && e[2].toLowerCase().indexOf(q) < 0) continue;
			hits.push([score < 0 ? 100 : (name === q ? -1 : score), e]);
		}
		hits.sort(function (a, b) { return a[0] - b[0] || a[1][0].length - b[1][0].length; });
		if (!hits.length) {
			results.innerHTML = '<li class="r-none">Nothing matches.</li>';
		}
		hits.slice(0, 12).forEach(function (h) {
			var li = document.createElement('li'), a = document.createElement('a');
			a.href = base + h[1][1];
			a.innerHTML = '<span class="r-name"></span><span class="r-where"></span>';
			a.firstChild.textContent = h[1][0];
			a.lastChild.textContent = h[1][2];
			li.appendChild(a);
			results.appendChild(li);
		});
		results.hidden = false;
	}
	function move(step) {
		var items = results.querySelectorAll('a');
		if (!items.length) return;
		if (selected >= 0) items[selected].removeAttribute('aria-selected');
		selected = (selected + step + items.length) % items.length;
		items[selected].setAttribute('aria-selected', 'true');
		items[selected].scrollIntoView({ block: 'nearest' });
	}
	input.addEventListener('input', function () { render(input.value); });
	input.addEventListener('keydown', function (ev) {
		if (ev.key === 'ArrowDown') { move(1); ev.preventDefault(); }
		else if (ev.key === 'ArrowUp') { move(-1); ev.preventDefault(); }
		else if (ev.key === 'Enter') {
			var items = results.querySelectorAll('a');
			if (items.length) location.href = items[selected >= 0 ? selected : 0].href;
		}
		else if (ev.key === 'Escape') { input.value = ''; render(''); input.blur(); }
	});
	document.addEventListener('keydown', function (ev) {
		if (ev.key === '/' && document.activeElement !== input && !/INPUT|TEXTAREA/.test(document.activeElement.tagName)) {
			input.focus();
			ev.preventDefault();
		}
	});
	document.addEventListener('click', function (ev) { if (!ev.target.closest('.search')) results.hidden = true; });
})();

