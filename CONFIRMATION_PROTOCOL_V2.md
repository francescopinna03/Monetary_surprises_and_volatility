# Preparazione del campione di conferma 2000-2012

Stato: implementazione preparatoria, specifica non congelata. Base `c224fe07dded3599bfb57f8be23e5e4c2032db53` del solo repository `Monetary_surprises_clone`.

Aggiornamento: `Run_confirmation_quality.sh` esegue ora l'audit OHLC, delle coppie
prezzo esatte e della selezione pre-PR. `Run_confirmation.sh readiness` verifica
la provenienza e riporta i blocchi. Vedere `CONFIRMATION_NEXT_STEPS.md` per comandi,
schemi dell'evidenza e discrepanze da risolvere prima di implementare la stima.
Il supporto PR canonico e' `(PR,PR+25]`, con cinque rendimenti, non `(PR+5,PR+25]`.

Il piano originale del 12 settembre e' conservato in `docs/Piano_conferma_2000-2012_originale.md`. Questa nota esplicita gli adattamenti necessari e i punti ancora da decidere. Non autorizza una stima sul campione di conferma.

**Cosa esegue questo aggiornamento.** `Run_confirmation.sh audit` costruisce l'inventario hash dei contratti 2000-2012, la copertura delle 164 celle previste, le sessioni osservate, il registro completo evento-radice-fase e i modelli di certificazione del calendario e del bar-label. Legge dai CSV soltanto timestamp e volume. Non carica le colonne prezzo e non calcola RV, BV, salti o picchi post-annuncio. La qualita' dei prezzi e la copertura puntuale delle finestre dovranno essere certificate nella fase successiva. Un intervallo fra prima e ultima barra non prova l'assenza di buchi interni o il calendario ufficiale di negoziazione.

`Run_confirmation.sh bridge` accetta un build v1 verificato mediante hash, controlla i metadati prima delle colonne outcome e usa soltanto il 2013-2025. Ristima la continuazione normale e lo stato sui controlli del campione di generazione, escludendo l'anno valutato. Calcola H1 e H2 sulla BV anomala del solo Bund, nella base grezza a otto colonne dichiarata nella specifica. Le scale dei futures provengono dai controlli PR di generazione. STOXX50E, espresso in percentuale nel file EA-EMPD, viene convertito in rendimento frazionale prima del confronto delle deviazioni standard; la sua scala proviene dagli eventi PR di generazione. Non si mescolano periodi o prezzi del nuovo campione nel ponte.

`Run_confirmation.sh check-protocol` elenca i requisiti ancora mancanti. I comandi `control-build`, `calibrate`, `freeze` ed `estimate` del v2 sono ora implementati e descritti in `CONFIRMATION_ESTIMATION_V2.md`. Non usare al loro posto `Run_final_analysis.sh freeze` o `Run_pipeline.m` sul nuovo archivio: il v1 costruisce gli outcome e non possiede la separazione richiesta dal piano.

**Separazione dei campioni.** Il ponte proposto sul 2011H2-2025 e' incompatibile con l'intenzione di usare tutto il 2000-2012 per conferma se quelle osservazioni orientano le scelte. Qui il ponte e' limitato al 2013-2025. Nessun dato 2026 entra nelle sue stime, anche se presente nel build storico. Si potranno usare covariate e controlli del 2000-2012 per la calibrazione ex ante secondo una regola fissata; gli outcome evento restano da costruire dopo il freeze.

**Calendario e orologio.** `GC_PC` identifica una finestra del dataset, non prova l'esistenza di una conferenza. Il calendario BCE del 2001 indica conferenze mensili e riunioni anche di mercoledi'. Si mantengono separati `source_window_present`, presenza effettiva e orario verificato. Il 17 settembre 2001 e l'8 ottobre 2008 richiedono revisione esplicita degli orari e della validita' delle finestre EA-EMPD. Si registrano le righe mancanti senza inventare eventi o conferenze.

Il 1 aprile 2004 lo scarto Europe/Berlin meno America/Chicago e' otto ore. Il 4 novembre 2004 e' sette, non sei. Il 1 novembre 2007 e' un caso di sei ore. Questi casi sono testati in Python e aggiunti al self-test MATLAB. Si usano fusi IANA e orari locali Europe/Berlin, non un CET fisso per tutte le stagioni.

**Oggetto matematico.** Le formule dei coni sono corrette per il peso angolare uniforme nella metrica grezza dichiarata. H1 e H2 sono funzionali nuovi, non una semplice rinomina del coefficiente MP della rotazione mediana. La matrice grezza recuperata e i valori predetti sono indipendenti dalla rappresentazione usata per stimarli. Entrate e autovettori cambiano coordinate se si cambia base; traccia e autovalori sono invarianti sotto similarita' ortogonale, non sotto ogni trasformazione JK che includa whitening o riscalamento. Una scala positiva mantiene i segni dei quadranti, ma cambia la ponderazione delle direzioni e quindi il funzionale di cono.

`Cone_functionals.m` e `confirmation_analysis/cones.py` usano la base `(u^2,z^2,2uz)`. `wild_contrast` impone direttamente il null della combinazione lineare, usa CR1 e segni comuni per meeting e calcola code unilaterali firmate. Non dimezza il p di un Wald bilaterale. La famiglia primaria prevista ha due test e 19.999 repliche; il gate di risoluzione passa. I test del ponte sono diagnostici sul campione gia' visto.

**Decisioni ancora aperte prima del freeze.** Il ponte registra i quattro criteri del piano. Se falliscono i criteri 1 o 3, riporta il fallback esterno omogeneo come candidato da discutere; non lo certifica automaticamente come equivalente alla coppia allineata. Il piano non specifica un fallback per il fallimento dei soli criteri 2 o 4. Il rapporto fra deviazione standard sugli eventi e sui controlli puo' riflettere la maggiore variabilita' degli annunci; il confronto dei p entro un fattore tre e' sensibile anche alla precisione Monte Carlo. Qualunque revisione avviene sul campione di generazione e va documentata prima del freeze.

Vanno inoltre definiti la metrica comune per l'eventuale sorgente azionaria ibrida, l'esatto vettore di nuisance, la lista finita dei test secondari e la correzione congiunta dell'intervallo di sufficienza. Un margine determinato dalla potenza misura una precisione raggiungibile, non equivale automaticamente alla trascurabilita' economica della storia. La soglia scientifica di riferimento e il margine calibrato saranno riportati distintamente. Un mancato rifiuto di H1 non dimostra eterogeneita' fra epoche senza un contrasto dedicato.

Il calendario USA resta non verificato finche' non esiste evidenza per i rilasci e per la copertura del calendario. I giovedi' alle 8:30 ET non possono essere convertiti in rilasci verificati per costruzione. Il matching per giorno non garantisce l'eliminazione della dipendenza tra notizie USA e indicatori di annuncio.

**Esecuzione del primo passaggio.** Dopo aver applicato l'aggiornamento, usare `bash Run_confirmation_prepare.sh PERCORSO_RUN_COMPLETA CARTELLA_NUOVI_CSV`. Il secondo percorso e' aggiuntivo rispetto a `Econometrics_data/Raw/Barchart_futures`; la ricerca legge soltanto file con nomi dei quattro futures previsti. La preparazione non sposta i dati e produce uno ZIP di diagnostica anche in caso di errore. I commit restano all'autore.

Fonti del controllo storico:

- ECB, calendario 2001 e conferenze mensili: https://www.ecb.europa.eu/press/pr/date/2000/html/pr000608_2.en.html
- ECB, decisione straordinaria del 17 settembre 2001: https://www.ecb.europa.eu/press/pr/date/2001/html/pr010917.en.html
- Federal Reserve, comunicato congiunto dell'8 ottobre 2008 alle 7:00 EDT, archivio FRASER: https://fraser.stlouisfed.org/files/docs/historical/FOMC/meetingdocuments/20081008statement.pdf
- NIST, regole DST e modifica del 2007: https://www.nist.gov/pml/time-and-frequency-division/popular-links/daylight-saving-time-dst
- US Department of Transportation, regola anteriore al 2007: https://www.transportation.gov/briefing-room/news-digest-18
