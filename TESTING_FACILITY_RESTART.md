# Ripartenza della testing facility, 13 settembre 2026

Base: ZIP della facility e riferimento GitHub `eaab00546b9919ef735c21a7bc64cea50b5860d8`.
Il comando principale e' `bash Run_testing_facility.sh`, eseguito dentro
`~/Desktop/Monetary_surprises_testing_facility/Monetary_surprises_clone`.
Non crea commit, non pubblica sul repository e non invoca freeze/estimate v2.

## Cosa esegue oggi

1. Classifica i CSV per anno del contratto e sposta quelli 2000-2012 da
   `~/Desktop/Econometrics_data/Raw/Barchart_futures` a
   `Barchart_futures_confirmation`, nella stessa directory Raw. Conserva tutto
   il ciclo di vita del contratto. Scrive piano, hash e contatore degli
   spostamenti. Rifiuta collisioni, file sconosciuti, link e sottocartelle;
   non cancella duplicati per decidere quale versione usare. E' ripetibile.
2. Cerca la build congelata `final_resume_20260911_174739_4124` nell'archivio
   consolidato, poi nella vecchia run usata soltanto come fonte di lettura.
   Verifica i suoi hash e copia esattamente gli input richiesti in
   `facility/runs/restart_*/generation/Econometrics_data`. Non copia tutti gli
   Output, non eredita file cleaned estranei, non copia i nuovi raw. Se il
   data root non contiene ancora i due manifest congelati, usa soltanto il
   piccolo archivio `Raw/Certification/generation_recovery_20260911`, sempre
   dopo il controllo SHA-256 contro `status.json`.
3. Lancia `Run_final_matlab_checks` in quella copia. Seleziona soltanto gli
   eventi 2013-2025 prima della costruzione delle finestre. La build di
   settembre comprende anche 5 febbraio e 19 marzo 2026: sono esclusi e
   registrati, lasciando intatti manifest e selezione congelati originali.
4. Scrive `shrinkage_1se_comparison.csv`, verificando che la penalizzazione
   scelta sia davvero la piu' forte nella banda. Il confronto con la regola
   `last` usa la medesima CV appena ottenuta: **non** ricostruisce i risultati
   di aprile. I coefficienti post-selezione restano descrittivi.
5. Esegue inventario e audit di qualita' con la sola directory di conferma
   esplicita. Produce anche le coppie apertura/chiusura per mese, convertite
   da UTC a Europe/Berlin. Non cerca CSV in Desktop o Downloads.
6. Esegue `Run_step28_calibration_only`, sulla griglia gia' dichiarata fino a
   500 meeting. Questo ingresso non chiama `Step28_sbb_panel`, data gate,
   gate spettrale empirico o SBB. Il risultato della calibrazione resta da
   osservare; non viene imposto un esito negativo.

Il comando scrive risultati e log in `facility/runs/restart_*` e uno ZIP
`Monetary_surprises_restart_*_results.zip` nella facility. Una fase MATLAB
fallita non impedisce gli audit Python indipendenti. Gli errori sono riportati
in `status.json` e danno exit code 2. Lo ZIP esclude copie Raw e cleaned.
La calibrazione sintetica puo' essere lunga; il log indica rango e G corrente.

Per ripetere soltanto una parte:

```bash
bash Run_testing_facility.sh --mode generation
bash Run_testing_facility.sh --mode repair
bash Run_testing_facility.sh --mode evidence
bash Run_testing_facility.sh --mode calibration
```

`generation` include ausiliari e calibrazione sintetica. `calibration` non
richiede alcun archivio empirico. `--generation-build`, `--recovery-root` e
`--data-root` permettono percorsi diversi senza cambiare il codice.
`MATLAB_BIN` e `PYTHON_BIN` accettano percorsi completi agli eseguibili.
`repair` ripete la separazione, gli ausiliari generazione e l'audit di conferma
completo, ma non rilancia la calibrazione Step 28 già terminata.

Per vedere soltanto il piano di separazione, prima di applicarlo:

```bash
../python_env/bin/python facility_archive.py \
  --data-root "$HOME/Desktop/Econometrics_data" \
  --output "../runs/split_preview_$(date +%Y%m%d_%H%M%S)"
```

Il launcher principale applica la separazione autorizzata dalla checklist.
Un'interruzione durante gli spostamenti conserva journal e lock. In quel caso
leggere `archive/status.json` e `archive/archive_plan.csv` prima di intervenire;
non eliminare alla cieca il lock.

## Correzioni alla checklist

`Run_final_matlab_checks` non include lo Step 28. Inoltre `Run_step28_gates`
non e' un comando puramente sintetico: dopo la calibrazione legge il pannello
empirico e puo' proseguire nei gate successivi. Per il punto 2.2 della
checklist usare il nuovo ingresso `Run_step28_calibration_only`.

La separazione per anno del contratto protegge gli ingressi ma non definisce
le date degli eventi, perche' i contratti hanno un ciclo di vita. Per questo
il rerun ausiliario controlla anche le date nella selezione congelata, prima
di estrarre i prezzi delle finestre. La pipeline MATLAB storica completa e'
distinta da questo rerun: non e' avviata automaticamente e non va usata come
stimatore confermativo.

## Evidenza Eurex gia' trovata

La [circolare 160/05, p. 2](https://www.eurexchange.com/resource/blob/291688/ef9332b8a52784228080a520919ec537/data/cf1602005e.pdf.pdf)
indica il **21 novembre 2005** per l'estensione alle 22:00. Le
[specifiche contrattuali in vigore dal 21 novembre 2005, p. 10](https://www.eurex.com/resource/blob/334472/1c0ac054e1cec9974271e8a20a5588a5/data/cs_history_21112005_en.pdf.pdf)
mostrano, nella tabella con le modifiche, il passaggio 08:00-19:00 a
08:00-22:00 per Schatz, Bobl e Bund. Non usare l'estrazione testuale del PDF
per scegliere fra numeri barrati e nuovi: la pagina e' stata controllata
visivamente.

Nei metadati dell'inventario allegato `20260912_152519_9603`, la prima sessione
con ultima etichetta alle 22:00 Europe/Berlin e' proprio 2005-11-21 per tutte
e tre le radici. La coincidenza conferma la data del cambio, non la semantica
delle barre.

Il [calendario Eurex 2011, p. 1](https://www.eurex.com/resource/blob/283130/b4c195865615cd3f92287e355a06efe4/data/tradingcalendar_2011_en.pdf)
indica 08:00-22:00 per la curva ma **07:50-22:00 per FESX**. Quindi le due
righe `all` della checklist non sono uno schedule valido per tutte le radici.
L'archivio ufficiale dei calendari e'
https://www.eurex.com/ex-en/trade/trading-calendar/trading-calendar-archive.

`config/eurex_trading_hours.csv` e' compilato con 35 righe riferite a periodi
documentati. Il revisore indicato e' Codex per la lettura documentale, non
Francesco Pinna. Gli URL e gli hash dei tredici calendari scaricati sono in
`eurex_trading_hours_sources.json`. I file 2001-2003 contengono il calendario
delle date ma non la tabella degli orari: quei giorni restano senza schedule,
anziche' ereditare orari presunti. Sono coperti 2000, 2004, l'ultima parte del
2005 e 2006-2012, quindi almeno un anno in ogni cella triennale del protocollo.
L'evidenza sulle barre e' prodotta come candidata: non e' promossa in automatico.

Il [calendario 2000, p. 2](https://www.eurex.com/resource/blob/289252/e667a61086fff75980e01a01b367eda5/data/tradingcalendar_2000_en.pdf)
riporta 08:00-19:00 per le tre radici di curva; quello del
[2012, p. 1 e nota 5](https://www.eurex.com/resource/blob/284994/e988f1cef4437150c0a74a5a8f285d64/data/tradingcalendar_2012_en.pdf)
conferma anche l'asta dopo il termine della negoziazione continua.

Il test a due estremi puo' essere inconclusivo anche con schedule esatto. Nei
metadati sono frequenti prima barra 08:00 e ultima 19:00/22:00: questa coppia
non coincide con nessuna delle due coppie previste dal test attuale. Non si
deve trasformare un'ultima transazione o un print al confine in una prova
automatica di interval_start/end. Se il test resta aperto, serve evidenza del
provider; non si abbassa la soglia per far passare il gate.

## Due audit, nell'ordine corretto

Il primo `--mode evidence` produce `confirmation_quality_first/primary_files.csv`.
Se esiste gia' uno schedule revisionato, produce anche `bar_label_candidates`.
Altrimenti, dopo aver completato lo schedule, rieseguire `--mode evidence`.
La promozione dei candidati richiede il revisore e la regola gia' previsti
da `CONFIRMATION_EVIDENCE_V2.md`; il launcher non firma al posto del revisore.

Dopo che `bar_label_evidence_v2.csv` e' stato promosso in
`Econometrics_data/Raw/Certification`, ripetere `--mode evidence`: la nuova
esecuzione scrive `confirmation_quality_second` e consuma la nuova evidenza.
Rifare l'inventario in quel passaggio evita anche di riutilizzare hash di un
calendario modificato dopo il primo audit. Il semplice nome "second" non
certifica il risultato: verificare `all_nonempty_files_label_verified` e gli
altri campi di `status.json`.

## Cosa resta prima della stima v2

La coda calendario compilata non e' contenuta nello ZIP della facility.
Restano la promozione e gli incroci elencati nella checklist; le 179 riunioni
sono una previsione, non un conteggio certificato da questo intervento.

Restano la revisione delle evidenze di barra, le cinque decisioni, la build
protetta e la lettura dei floor prima del freeze, come richiesto dalla
checklist. Questi moduli esistono gia' nel codice allegato. Due limiti vanno
pero' mantenuti visibili: `readiness.py` conserva alcuni `False` fissi
(session review ed external timing) e `freeze.py` non tratta quel report come
un gate unico; inoltre `calibrate.py` usa OIS 1Y come proxy della coordinata
Schatz che verra' usata nella stima primaria. I suoi floor non certificano
automaticamente la potenza nell'altra metrica. Non avviare il freeze soltanto
perche' i comandi esistono o il calendario e' stato promosso.

Questa consegna chiude l'avvio del lavoro eseguibile oggi. Non dichiara chiusa
la conferma e non avvia la pipeline sul campione unificato.
