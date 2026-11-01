# Installed module/provider duplication audit — dev080

Actual packaged inventory: 101 modules. All scientific modules and historical external packages stay byte-identical; only Builder 1.2.0 changes relative to verified dev079.

Standard state uses existing Dataset/Graph/Script/Instrument/Document/Managed Resource authorities. Unsupported module configuration resets to disabled defaults. Missing plugins and unknown documents are omitted; explicit generation-bound preparation receipts survive provider uninstall. No executable clone callbacks or private clone file routines were added.

| Module | Version | Kind | Configuration fields | Viewer providers | Classification |
|---|---|---|---:|---|---|
| acq.rigol_csv | 2.0.0 | acquisition | 13 | — | optional legacy fallback |
| acq.generic_csv | 2 | acquisition | 4 | — | optional legacy fallback |
| acq.wav | 1.0.0 | acquisition | 1 | — | optional legacy fallback |
| acq.audio | 1.0.1 | acquisition | 5 | — | optional legacy fallback |
| acq.xas | 1.0.1 | acquisition | 14 | — | optional legacy fallback |
| acq.nmr | 1.0.0 | acquisition | 4 | — | optional legacy fallback |
| acq.nmr_multidimensional | 1.0.0 | acquisition | 3 | — | optional legacy fallback |
| gxtxt.ir_waveform | 3.6.2 | analysis | 19 | — | optional legacy fallback |
| gxtxt.ir_identify | 2.0.2 | analysis | 3 | — | optional legacy fallback |
| acq.tektronix_current_log | 2 | acquisition | 5 | — | optional legacy fallback |
| acq.touchstone | 1.0.0 | acquisition | 1 | — | optional legacy fallback |
| acq.image_binary | 1.2.0 | acquisition | 1 | — | optional legacy fallback |
| acq.pdf_document | 1.0.1 | acquisition | 1 | — | optional legacy fallback |
| acq.sketch_dataset | 1.0.0 | acquisition | 1 | — | optional legacy fallback |
| acq.geometry_3d | 1.1.0 | acquisition | 1 | — | optional legacy fallback |
| acq.crystal_density | 1.0.0 | acquisition | 1 | — | optional legacy fallback |
| acq.text_document | 1.0.4 | acquisition | 4 | — | optional legacy fallback |
| acq.molecule_structure | 1.0.1 | acquisition | 1 | — | optional legacy fallback |
| sequence.table_join | 3 | analysis | 3 | — | optional legacy fallback |
| dataset.extract | 1.3.0 | analysis | 4 | — | optional legacy fallback |
| analysis.audio_decode | 2.0.1 | analysis | 2 | — | optional legacy fallback |
| curve.replicate_analysis | 15.2 | analysis | 11 | — | optional legacy fallback |
| analysis.fft_spectrum | 2.2.0 | analysis | 13 | — | optional legacy fallback |
| curvefit.family_global | 6 | analysis | 11 | — | optional legacy fallback |
| analysis.time_dependent_fft | 1.3.3 | analysis | 9 | — | optional legacy fallback |
| analysis.cross_spectral_transfer | 1.1.3 | analysis | 7 | — | optional legacy fallback |
| analysis.welch_spectrum | 1.1.0 | analysis | 7 | — | optional legacy fallback |
| analysis.fractional_octave_spectrum | 1.1.0 | analysis | 5 | — | optional legacy fallback |
| analysis.envelope_spectrum | 1.1.0 | analysis | 9 | — | optional legacy fallback |
| analysis.harmonic_analysis | 1.1.0 | analysis | 6 | — | optional legacy fallback |
| analysis.cepstrum | 1.1.1 | analysis | 6 | — | optional legacy fallback |
| analysis.spectroscopy.ir | 1.1.2 | analysis | 19 | — | optional legacy fallback |
| analysis.spectroscopy.nmr | 1.0.0 | analysis | 9 | — | optional legacy fallback |
| analysis.spectroscopy.uvvis | 1.1.2 | analysis | 5 | — | optional legacy fallback |
| analysis.spectroscopy.uvvis_exploration | 1.0.2 | analysis | 8 | — | optional legacy fallback |
| analysis.spectral_features | 1.1.0 | analysis | 3 | — | optional legacy fallback |
| model.spice_build_validate | 4 | analysis | 16 | — | optional legacy fallback |
| analysis.xas.normalize | 1.0.2 | analysis | 11 | — | optional legacy fallback |
| analysis.dataset_expression | 1.0.1 | analysis | 8 | — | optional legacy fallback |
| analysis.statistics.descriptive | 1.1.0 | analysis | 10 | — | optional legacy fallback |
| analysis.statistics.grouped | 1.0.0 | analysis | 7 | — | optional legacy fallback |
| analysis.statistics.correlation | 1.0.1 | analysis | 6 | — | optional legacy fallback |
| analysis.statistics.distribution | 1.0.1 | analysis | 10 | — | optional legacy fallback |
| analysis.statistics.outliers | 1.0.1 | analysis | 6 | — | optional legacy fallback |
| analysis.statistics.weighted | 1.0.1 | analysis | 8 | — | optional legacy fallback |
| analysis.statistics.tests | 1.0.1 | analysis | 9 | — | optional legacy fallback |
| analysis.statistics.anova | 1.0.1 | analysis | 7 | — | optional legacy fallback |
| analysis.regression | 1.0.1 | analysis | 11 | — | optional legacy fallback |
| analysis.statistics.pca | 1.0.1 | analysis | 10 | — | optional legacy fallback |
| analysis.statistics.resampling | 1.0.1 | analysis | 11 | — | optional legacy fallback |
| math.numeric | 1.16.0 | analysis | 0 | — | standard CORE ownership |
| math.magnetics | 1.2.0 | analysis | 0 | — | standard CORE ownership |
| math.rf_network | 1.2.0 | analysis | 0 | — | standard CORE ownership |
| math.signal | 1.2.0 | analysis | 0 | — | standard CORE ownership |
| demo.numeric.interpolation | 1.0.4 | analysis | 2 | — | optional legacy fallback |
| demo.numeric.smoothing | 1.0.2 | analysis | 7 | — | optional legacy fallback |
| demo.numeric.calculus | 1.0.1 | analysis | 2 | — | optional legacy fallback |
| demo.numeric.regression | 1.0.1 | analysis | 5 | — | optional legacy fallback |
| demo.numeric.statistics | 1.0.1 | analysis | 4 | — | optional legacy fallback |
| demo.numeric.nonlinear_fit | 1.0.5 | analysis | 0 | — | standard CORE ownership |
| demo.numeric.peaks | 1.0.2 | analysis | 8 | — | optional legacy fallback |
| library.spectroscopy.ir.reference | 1.0.1 | analysis | 0 | — | standard CORE ownership |
| plot.dataset | 3.13.0 | analysis | 5 | — | small native schema compatibility adapter; module configuration fallback |
| demo.numeric.uncertainty | 1.0.1 | analysis | 5 | — | optional legacy fallback |
| library.spectroscopy.nmr.reference | 1.0.0 | analysis | 0 | — | standard CORE ownership |
| demo.numeric.root_finding | 1.0.2 | analysis | 7 | — | optional legacy fallback |
| demo.numeric.minimization | 1.0.2 | analysis | 8 | — | optional legacy fallback |
| analysis.octave_script | 1.3.0 | analysis | 7 | octave_script_editor | small native schema compatibility adapter; module configuration fallback |
| demo.environmental.levoglucosan_campaign | 1.2.2 | analysis | 13 | — | optional legacy fallback |
| demo.visualization.surface3d | 1.0.3 | analysis | 0 | — | standard CORE ownership |
| analysis.python_script | 1.1.0 | analysis | 5 | python_script_editor | optional legacy fallback |
| demo.geospatial.ticino_valley_3d | 2.0.0 | analysis | 0 | — | standard CORE ownership |
| tool.script_module_builder | 1.2.0 | tool | 0 | — | standard CORE ownership |
| viewer.curve_digitizer | 1.2.2 | viewer | 0 | curve_digitizer | optional legacy fallback |
| viewer.curve_trace_assistant | 0.5.0 | viewer | 0 | curve_trace_assistant | standard CORE ownership |
| viewer.pdf_ocr | 1.0.3 | viewer | 0 | pdf_ocr | small native schema compatibility adapter; module configuration fallback |
| viewer.spectral_library | 1.0.14 | viewer | 0 | spectral_library | optional legacy fallback |
| viewer.table_extractor | 1.0.1 | viewer | 0 | table_extractor | small native schema compatibility adapter; module configuration fallback |
| viewer.document_extractors | 1.0.1 | viewer | 0 | generic_ocr;table_extractor | standard CORE ownership |
| viewer.reference_library | 1.0.1 | viewer | 0 | reference_library | standard CORE ownership |
| viewer.scientific_library_manager | 1.0.1 | viewer | 0 | scientific_library_manager | standard CORE ownership |
| viewer.engine_3d | 0.1.4 | viewer | 0 | engine_3d | standard CORE ownership |
| analysis.digitization_quality | 0.1.0 | viewer | 0 | digitization_quality | standard CORE ownership |
| viewer.native_3d | 0.9.4 | viewer | 3 | native_3d | small native schema compatibility adapter; module configuration fallback |
| viewer.xas_spectra | 1.0.4 | viewer | 0 | xas_spectra | standard CORE ownership |
| viewer.nmr_reference | 1.0.0 | viewer | 0 | nmr_reference | standard CORE ownership |
| viewer.nmr_spectrum | 1.0.1 | viewer | 0 | nmr_spectrum | standard CORE ownership |
| viewer.section_profile | 1.0.0 | viewer | 0 | section_profile | standard CORE ownership |
| viewer.crystal_structure | 1.0.1 | viewer | 0 | crystal_structure | standard CORE ownership |
| viewer.molecule_3d | 1.0.0 | viewer | 0 | molecule_3d | standard CORE ownership |
| viewer.nmr_multidimensional | 1.0.0 | viewer | 0 | nmr_multidimensional | standard CORE ownership |
| viewer.curve_viewer | 0.1.0 | viewer | 0 | curve_viewer | optional legacy fallback |
| viewer.interactive_curve_builder | 1.0.0 | viewer | 0 | interactive_curve_builder | standard CORE ownership |
| viewer.curve_workbench | 2.13.1 | viewer | 0 | curve_workbench | small native schema compatibility adapter; module configuration fallback |
| viewer.3d_workbench | 0.1.0 | viewer | 0 | workbench_3d | small native schema compatibility adapter; module configuration fallback |
| viewer.dataset_curve_fit | 0.3.14 | viewer | 0 | dataset_curve_fit | optional legacy fallback |
| export.native2d_presentation | 1.0.0 | export | 0 | — | standard CORE ownership |
| viewer.scientific_worksheet | 1.1.1 | viewer | 0 | scientific_worksheet | optional legacy fallback |
| export.native3d_geometry | 1.0.0 | export | 0 | — | standard CORE ownership |
| analysis.definition_demo | 1 | analysis | 2 | — | optional legacy fallback |
| export.session_html | 1.0.4 | export | 0 | — | standard CORE ownership |

Also audited 2 Instrument Module descriptors under the existing CORE Instrument/Library authority; their typed equipment setup fields and actual Library snapshot links remain independent. Viewer declarations are recorded in full in module-audit.json, alongside registered Workspace provider schemas.

The only compatibility schema adapters are registered Workspaces, historical Curve/PDF OCR/Table Extractor/3D Workbench/staging Workspaces and Plot Dataset scenes (excluded), the historical Octave author-code document (inert bytes), and Native3D one-source viewer documents (dependency-validated, unsafe source paths omitted). They describe public native formats, use no module-ID clone switch, and preserve historical data interpretation. New plugins use exact provider/format/version policy declarations and the existing registry owner receipt.

All analysis/raw/channel/cache/report/log payload directories and unknown metadata are omitted conservatively, including uninstalled-module output trees. CORE graph transport TSV/render-cache exceptions are retained as explicit historical ownership documentation, even though whole analysis state is now excluded. SHA-256 checks verify integrity only and never classify scientific ownership.

The headless independent-module fixture installs new descriptors only into a disposable framework and proves valid/absent/invalid policies, actual standard analysis execution on newly acquired data, exact author parameters, external references, omitted opaque/mixed data, stale/deleted resources, and provider uninstall without adding any fixture ID to CORE.
