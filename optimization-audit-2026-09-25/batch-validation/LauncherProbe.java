import java.lang.management.ManagementFactory;
import java.util.Arrays;
public class LauncherProbe {
    public static void main(String[] args) {
        System.out.println("PROBE_DIRECTORY=" + System.getProperty("user.dir"));
        System.out.println("PROBE_ARGS=" + Arrays.toString(args));
        System.out.println("PROBE_VM=" + ManagementFactory.getRuntimeMXBean().getInputArguments());
        String code = System.getenv("HORIZONS_PROBE_EXIT");
        System.exit(code == null ? 0 : Integer.parseInt(code));
    }
}