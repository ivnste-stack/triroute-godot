// Port of makeCountry(), genCountryName(), genFlag() (RNG part), personName(), newMinister() and the colour
// assignment of startBoard(). Field evaluation order follows the JS object literals exactly.
#include "states.h"
#include "jsmath.h"
#include "rng.h"
#include "statedata.h"

#include <algorithm>
#include <cmath>
#include <map>
#include <set>

namespace tr {

namespace {

struct R {
	Mulberry m;
	explicit R(uint32_t s) : m(s) {}
	double operator()() { return m(); }
	double rnd(double a, double b) { return a + m() * (b - a); }
	int rint(int a, int b) { return int(std::floor(rnd(a, b + 1.0))); }
	bool chance(double p) { return m() < p; }
	template <class V>
	const typename V::value_type &pick(const V &v) { return v[size_t(std::floor(m() * v.size()))]; }
};

// UTF-8 <-> code points (the names are Cyrillic; JS counts UTF-16 units, which is one per letter here)
std::u32string decode(const std::string &s) {
	std::u32string out;
	for (size_t i = 0; i < s.size();) {
		unsigned char c = s[i];
		char32_t cp;
		int n;
		if (c < 0x80) { cp = c; n = 1; }
		else if ((c >> 5) == 6) { cp = c & 0x1F; n = 2; }
		else if ((c >> 4) == 14) { cp = c & 0x0F; n = 3; }
		else { cp = c & 0x07; n = 4; }
		for (int k = 1; k < n; k++) cp = (cp << 6) | (s[i + k] & 0x3F);
		out.push_back(cp);
		i += n;
	}
	return out;
}
std::string encode(const std::u32string &s) {
	std::string out;
	for (char32_t c : s) {
		if (c < 0x80) out.push_back(char(c));
		else if (c < 0x800) { out.push_back(char(0xC0 | (c >> 6))); out.push_back(char(0x80 | (c & 0x3F))); }
		else { out.push_back(char(0xE0 | (c >> 12))); out.push_back(char(0x80 | ((c >> 6) & 0x3F))); out.push_back(char(0x80 | (c & 0x3F))); }
	}
	return out;
}

// n.replace(/([аеиіоуяю])([аеиіоуяюї])/g, a+"р"+b)
std::u32string fix_vowels(const std::u32string &n) {
	static const std::u32string V1 = U"аеиіоуяю", V2 = U"аеиіоуяюї";
	std::u32string out;
	for (size_t i = 0; i < n.size();) {
		if (i + 1 < n.size() && V1.find(n[i]) != std::u32string::npos && V2.find(n[i + 1]) != std::u32string::npos) {
			out.push_back(n[i]);
			out.push_back(U'р');
			out.push_back(n[i + 1]);
			i += 2;
		} else {
			out.push_back(n[i]);
			i++;
		}
	}
	return out;
}

std::string country_name(R &r, std::set<std::string> &used) {
	for (int k = 0; k < 200; k++) {
		std::string n = r.pick(SYL_A);
		n += r.pick(SYL_B);
		n += r.pick(SYL_C);
		std::u32string u = fix_vowels(decode(n));
		if (u.size() < 5 || u.size() > 11) continue;
		std::string s = encode(u);
		if (used.count(s)) continue;
		used.insert(s);
		return s;
	}
	return "Земля " + std::to_string(used.size());
}

std::string person(R &r) {
	std::string n = r.pick(FIRST);
	n += " ";
	n += r.pick(LAST);
	return n;
}

Flag flag(R &r) {
	std::vector<int> cols(FLAGCOL.size());
	for (size_t i = 0; i < cols.size(); i++) cols[i] = int(i);
	for (int i = int(cols.size()) - 1; i > 0; i--) {   // shuffle()
		int j = int(std::floor(r() * (i + 1)));
		std::swap(cols[i], cols[j]);
	}
	Flag f;
	for (int i = 0; i < 4; i++) f.cols[i] = cols[i];
	f.type = r.rint(0, 8);
	if (r.chance(.5)) f.emblem = r.rint(0, 2);
	return f;
}

} // namespace

std::vector<State> generate_states(uint32_t seed, const World &w, uint32_t *rng_state) {
	R r(seed ^ 0x5bd1e995u);
	std::set<std::string> used;
	std::vector<State> out;
	for (size_t i = 0; i < w.countries.size(); i++) {
		const Country &geo = w.countries[i];
		State c;
		c.id = int(i);
		const Ideol &ide = r.pick(IDEOL);
		const Trait &tr_ = r.pick(TRAITS);
		double sizeF = std::sqrt(geo.land_share * 15);
		double p1 = r.rnd(8, 70);
		double p2 = r.rnd(.6, 1.6);
		c.pop = clampd(p1 * sizeF * p2, 2, 400);
		c.dev = r.rnd(.15, 1);
		double gdpPc = (3 + (62 - 3) * (c.dev * c.dev)) * 1000;
		c.gdp = c.pop * gdpPc / 1000;
		c.name = country_name(r, used);
		if (!geo.name.empty()) c.name = geo.name;   // the Earth
		if (geo.epop > 0) {   // the Earth: real people and wealth (the rolls above keep the RNG in step)
			c.pop = clampd(geo.epop, 1, 400);
			c.dev = clampd(geo.edev, .15, 1);
			c.gdp = c.pop * (3 + (62 - 3) * (c.dev * c.dev)) * 1000 / 1000;
		}
		c.ideol = ide.id;
		c.gov = ide.gov;
		c.title = ide.title;
		c.trait = tr_.id;
		c.full = std::string(ide.gov) + " " + c.name;
		c.flag = flag(r);
		c.leader = person(r);
		c.leader_age = r.rint(42, 74);
		c.treasury = c.gdp * r.rnd(.02, .06);
		c.debt = c.gdp * r.rnd(.2, .9);
		r.rint(12, 28);   // tax: income, vat, corp, tariff (not used by the logistics game)
		r.rint(12, 22);
		r.rint(12, 28);
		r.rint(2, 10);
		for (const auto &m : MIN) c.budget.push_back(m.sh * .72 * r.rnd(.8, 1.2) * (std::string(m.id) == "defense" && tr_.a > .5 ? 1.6 : 1));
		for (size_t k = 0; k < MIN.size(); k++) c.quality.push_back(r.rnd(35, 65));
		for (size_t k = 0; k < MIN.size(); k++) {   // newMinister(m.id, 0, .06+(1-tr.c)*.28)
			double cp = .06 + (1 - tr_.c) * .28;
			r.rnd(2, 9);
			person(r);
			r.rint(34, 68);
			r.rint(30, 90);
			if (r.chance(cp)) r.rnd(.3, .8);
			else r.rnd(0, .12);
		}
		for (int k = 0; k < GROUPS_N; k++) c.mood.push_back(r.rnd(40, 60));
		c.stability = r.rnd(45, 70);
		c.infl = r.rnd(2, 7);
		c.unemp = r.rnd(3.5, 11);
		c.tech = c.dev * 60 + r.rnd(0, 15);
		c.election_in = r.rint(12, 48);
		c.corr = clampd(10 + (1 - tr_.c) * 34 + r.rnd(-6, 8), 5, 70);
		for (const auto &rs : RES) {
			double dep = r.chance(.45) ? 0 : r.rnd(.2, 1.3);
			if (r.chance(.16)) dep = r.rnd(2, 4.2);
			std::string id = rs.id, cat = rs.cat;
			if (cat == "tech") dep = c.dev > .55 ? r.rnd(.4, 2.5) * c.dev : r.rnd(0, .3);
			if (id == "grain" || id == "timber") dep = r.rnd(.3, 2.4);
			if (id == "steel") dep = r.rnd(.2, 1.8) * (.5 + c.dev * .5);
			c.deposit.push_back(dep);
		}
		auto add_law = [&](const std::string &l) {
			if (std::find(c.laws.begin(), c.laws.end(), l) == c.laws.end()) c.laws.push_back(l);
		};
		static const std::vector<std::string> L1 = {"censor", "policestate", "conscription"}, L2 = {"press", "egov", "free_med", "nabu"},
											   L3 = {"nuclear", "green", "util_sub", "min_wage"};
		if (r.chance(.15)) add_law(r.pick(L1));
		if (c.ideol == "dem" || c.ideol == "soc") add_law(r.pick(L2));
		if (c.ideol == "aut" || c.ideol == "jun") {
			add_law("policestate");
			if (r.chance(.6)) add_law("censor");
		}
		if (r.chance(.3)) add_law(r.pick(L3));
		size_t def = 0;
		for (size_t k = 0; k < MIN.size(); k++)
			if (std::string(MIN[k].id) == "defense") def = k;
		bool consc = std::find(c.laws.begin(), c.laws.end(), "conscription") != c.laws.end();
		c.mil = (c.budget[def] * c.gdp) * r.rnd(8, 14) + (consc ? 20 : 0);
		out.push_back(std::move(c));
	}
	// colours: neighbours differ, the least used first, a little randomness among the three best
	std::map<std::string, int> usedCol;
	for (auto &c : out) {
		std::set<std::string> nc;
		for (int j : w.countries[c.id].neighbors)
			if (j >= 0 && j < int(out.size()) && !out[j].color.empty()) nc.insert(out[j].color);
		std::vector<std::string> opts;
		for (auto &x : COUNTRY_COLS)
			if (!nc.count(x)) opts.push_back(x);
		std::stable_sort(opts.begin(), opts.end(), [&](const std::string &a, const std::string &b) { return usedCol[a] - usedCol[b] < 0; });
		int k = r.rint(0, std::min(2, int(opts.size()) - 1));
		if (k >= 0 && k < int(opts.size())) c.color = opts[k];
		else c.color = r.pick(COUNTRY_COLS);
		usedCol[c.color]++;
	}
	if (rng_state) *rng_state = r.m.state();
	return out;
}

} // namespace tr
