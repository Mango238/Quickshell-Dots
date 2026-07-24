use sysinfo::System; // Asegúrate de importar los traits necesarios
use std::io::{self, Write};
use std::time;

fn main() {
    let mut sys = System::new();
    let duration = time::Duration::from_secs(60);

    sys.refresh_cpu_usage();

    std::thread::sleep(time::Duration::from_millis(200));
    
    loop {
        // Refrescamos la información de la CPU
        sys.refresh_cpu_usage();
        
        // Calculamos la media
        let mut cpu_midia: f32 = 0.0; // ¡Importante! Reiniciar a 0 en cada vuelta
        let cpus = sys.cpus();
        
        for cpu in cpus {
            cpu_midia += cpu.cpu_usage();
        }

        if !cpus.is_empty() {
            cpu_midia /= cpus.len() as f32;
        }

        // Imprimimos solo el número (es más fácil de parsear en QML si evitas el '%')
        // O lo dejas si lo prefieres. Aquí lo dejo limpio.
        print!("{:.1}", cpu_midia as u8); 
        
        // CRÍTICO: Forzar la salida inmediata hacia Quickshell
        io::stdout().flush().unwrap();
        
        // Imprimir salto de línea después del flush o usar println! con flush posterior
        println!(); 

        // Esperamos antes de la siguiente medición
        std::thread::sleep(duration);
    }
}
