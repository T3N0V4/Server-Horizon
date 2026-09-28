import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;
import java.util.Objects;
import java.util.TreeMap;
import java.util.TreeSet;
import DistantHorizons.libraries.electronwill.nightconfig.core.Config;
import DistantHorizons.libraries.electronwill.nightconfig.toml.TomlParser;

public class ValidateConfigs {
    record Change(Object before, Object after) {}

    static Map<String, Object> parse(Path path) throws Exception {
        try (Reader reader = Files.newBufferedReader(path, StandardCharsets.UTF_8)) {
            Map<String, Object> values = new TreeMap<>();
            flatten("", new TomlParser().parse(reader), values);
            return values;
        }
    }

    static void flatten(String prefix, Config config, Map<String, Object> result) {
        for (Map.Entry<String, Object> entry : config.valueMap().entrySet()) {
            String key = prefix.isEmpty() ? entry.getKey() : prefix + "." + entry.getKey();
            if (entry.getValue() instanceof Config nested) {
                flatten(key, nested, result);
            } else {
                result.put(key, entry.getValue());
            }
        }
    }

    static void check(Path current, Map<String, Change> expected, StringBuilder output) throws Exception {
        Map<String, Object> before = parse(Path.of(current + ".bak"));
        Map<String, Object> after = parse(current);
        if (!before.keySet().equals(after.keySet())) {
            throw new IllegalStateException(current + ": keys added or removed");
        }
        var changed = new TreeSet<String>();
        for (String key : before.keySet()) {
            if (!Objects.equals(before.get(key), after.get(key))) changed.add(key);
        }
        if (!changed.equals(new TreeSet<>(expected.keySet()))) {
            throw new IllegalStateException(current + ": unexpected changed keys " + changed);
        }
        output.append("PASS ").append(current).append(": both complete TOML documents parsed; ")
                .append(after.size()).append(" scalar/list keys; no keys added or removed; ")
                .append(changed.size()).append(" intended changes.\n");
        for (String key : changed) {
            Change change = expected.get(key);
            Object oldValue = before.get(key), newValue = after.get(key);
            if (!Objects.equals(oldValue, change.before()) || !Objects.equals(newValue, change.after())) {
                throw new IllegalStateException(current + ": wrong value or type for " + key
                        + ": " + oldValue + " -> " + newValue);
            }
            output.append("  ").append(key).append(": ")
                    .append(oldValue).append(" [").append(oldValue.getClass().getSimpleName()).append("] -> ")
                    .append(newValue).append(" [").append(newValue.getClass().getSimpleName()).append("]\n");
        }
    }

    public static void main(String[] args) throws Exception {
        var output = new StringBuilder("Configuration validation: 2026-09-25\n")
                .append("Parser: relocated NightConfig TomlParser from installed Distant Horizons 2.3.4-b JAR.\n")
                .append("Read-only comparison against config/*.toml.bak. Minecraft and the world were not started.\n\n");
        check(Path.of("config/c2me.toml"), Map.of(
                "globalExecutorParallelism", new Change("default", 3)), output);
        check(Path.of("config/DistantHorizons.toml"), Map.of(
                "server.maxGenerationRequestDistance", new Change(4096, 256),
                "server.maxSyncOnLoadRequestDistance", new Change(4096, 256),
                "common.multiThreading.numberOfThreads", new Change(8, 2),
                "common.lodBuilding.dataCompression", new Change("LZMA2", "LZ4")), output);
        output.append("\nPASS: exactly 1 C2ME change and 4 Distant Horizons changes; expected values and Java types confirmed.\n")
                .append("Syntax and semantic key comparison only; no runtime performance measurement or mod startup test.\n");
        Files.writeString(Path.of("optimization-audit-2026-09-25/validation/config-validation.txt"),
                output.toString(), StandardCharsets.UTF_8);
        System.out.print(output);
    }
}
