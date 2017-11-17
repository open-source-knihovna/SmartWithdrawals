![logo KohaCZ](https://github.com/open-source-knihovna/SmartWithdrawals/blob/master/SmartWithdrawals/koha_cz.png "Logo Česká komunita Koha")
![logo R-Bit Technology, s.r.o.](https://github.com/open-source-knihovna/SmartWithdrawals/blob/master/SmartWithdrawals/logo.png "Logo R-Bit Technology, s.r.o.")
![logo MK ČR](https://github.com/open-source-knihovna/SmartWithdrawals/blob/master/SmartWithdrawals/logo_mkcr.png "Logo MK ČR")
Plugin vytvořila společnost R-Bit Technology, s. r. o. ve spolupráci s českou komuntou Koha, za finančního přispění Ministerstva kultury České republiky.

# Úvod

Zásuvný modul 'Inteligentní odpisy a přesuny' byl vytvořen jako nástroj pro systematické vyhledávání jednotek vhodných k odepsání z knižního fondu. Využitím tohoto nástroje si knihovny mohou vybírat kandidáty na vyřazení podle souboru stanovených parametrů. Výběr není subjektivní či pocitový, ale je založen na reálných datech o jednotkách jako je např. stáří jednotky či frekvence výpůjček v určitém období.

Pro skutečně snadnou práci lze nastavení vyhledávacích parametrů uložit, pojmenovat, uvést požadovaný počet jednotek a celou předvolbu případně doplnit i delším slovním popisem. Uložené předvolby se dají snadno duplikovat a vytvářet tak velmi rychle různé varianty nastavení. Vyhledané výsledky lze pochopitelně stáhnout ve standardních formátech souborů a využít je k dalšímu zpracovaní (např. vytisknout v tabulkovém procesoru - jako LibreCalc nebo MS Excel).

# Instalace

## Zprovoznění Zásuvných modulů

Institut zásuvných modulů umožňuje rozšiřovat vlastnosti knihovního systému Koha dle specifických požadavků konkrétní knihovny. Zásuvný modul se instaluje prostřednictvím balíčku KPZ (Koha Plugin Zip), který obsahuje všechny potřebné soubory pro správné fungování modulu.

Pro využití zásuvných modulů je nutné, aby správce systému tuto možnost povolil v nastavení.

Nejprve je zapotřebí provést několik změn ve vaší instalaci Kohy:

* V souboru koha-conf.xml změňte `<enable_plugins>0</enable_plugins>` na `<enable_plugins>1</enable_plugins>`
* Ověřte, že cesta k souborům ve složce `<pluginsdir>` existuje, je správná a že do této složky může webserver zapisovat
* Pokud je hodnota `<pluginsdir>` např. `/var/lib/koha/kohadev/plugins`, vložte následující kód do konfigurace webserveru:
```
Alias /plugin/ "/var/lib/koha/kohadev/plugins/"
<Directory "/var/lib/koha/kohadev/plugins">
  Options +Indexes +FollowSymLinks
  AllowOverride All
  Require all granted
</Directory>
```
* Restartujte webserver

Jakmile je nastavení připraveno, budete potřebovat změnit systémovou konfigurační hodnotu UseKohaPlugins v administraci Kohy. Na stránce Nástroje pak najdete odkaz Zásuvné moduly. Aktuální verzi pluginu [stahujte v sekci Releases](https://github.com/open-source-knihovna/SmartWithdrawals/releases).

## Nastavení specifické pro modul inteligentních odpisů

Před prvním spuštěním nástroje nejprve zvolte položku "Nastavit" v menu "Akce". Konfigurační stránka umožní vybrat vhodné číselníky autorizovaných hodnot, pomocí nichž budete následně vytvářet a ukládat uživatelské předvolby výběru odepisovaných jednotek. Pokud některý z číselníků nepoužíváte, ponechte ve výběru hodnotu '(neuvedeno)'.

Více informací, jak s nástrojem pracovat naleznete na [wiki](https://github.com/open-source-knihovna/SmartWithdrawals/wiki)
