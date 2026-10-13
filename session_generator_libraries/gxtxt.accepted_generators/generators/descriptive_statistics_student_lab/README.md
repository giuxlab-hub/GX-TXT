# Descriptive Statistics Student Lab

Deterministic ready-to-run Session Generator for `analysis.statistics.descriptive`.

The generated Session contains numeric variables with compatible voltage units (`V` and `mV`), an incompatible current variable (`A`), constant and signed data, single/two-value teaching columns, explicit `NaN`, `+Inf` and `-Inf` values, a persisted X-range Dataset Selection, stable variable identities, known reference values, and a preconfigured production-module run.

The default run selects samples 3 through 12 and analyzes `voltage_V`, `voltage_mV`, `current_A`, and `constant_V`. Automatic graphics are enabled. The expected grouping is two unit families, producing histogram and box/whisker variants for each family.

After the first run, students can add `signed_V`, `single_value_V`, or `two_values_V`, change the Selection, switch the NaN/Inf policy, and change histogram or box/whisker options.

The generated Session also contains `STUDENT_GUIDE.txt`, which walks the student through the first run and five follow-up exercises.
