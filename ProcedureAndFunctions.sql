- Un procedimiento almacenado para registrar una venta.
- Validar que el cliente exista.
- Verificar que el stock sea suficiente antes de procesar la venta.
- Si no hay stock suficiente, Notificar por medio de un mensaje en consola usando RAISE.
- Si hay stock, se realiza el registro de la venta.

CREATE OR REPLACE FUNCTION registrar_ventas(
    p_cliente_id   INTEGER,
    p_producto_id  INTEGER,
    p_cantidad     INTEGER,
    p_precio_unitario NUMERIC DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_stock INTEGER;
    v_venta_id INTEGER;
    v_cliente_exists INTEGER;
    v_precio_catalogo NUMERIC;
    v_precio_unitario NUMERIC;
BEGIN
    SELECT 1 INTO v_cliente_exists
    FROM clientes
    WHERE id = p_cliente_id;

    IF v_cliente_exists IS NULL THEN
        RAISE EXCEPTION 'Cliente con id % no existe', p_cliente_id;
    END IF;

    SELECT stock, precio INTO v_stock, v_precio_catalogo
    FROM productos
    WHERE id = p_producto_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Producto con id % no existe', p_producto_id;
    END IF;


    IF v_stock < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente para producto %. Disponible: %, solicitado: %',
                        p_producto_id, v_stock, p_cantidad;
    END IF;


    IF p_precio_unitario IS NULL THEN
        IF v_precio_catalogo IS NULL THEN
            RAISE EXCEPTION 'No se proporcionó precio_unitario y producto no tiene precio en catálogo';
        END IF;
        v_precio_unitario := v_precio_catalogo;
    ELSE
        v_precio_unitario := p_precio_unitario;
    END IF;

    INSERT INTO ventas(fecha, cliente_id)
    VALUES (CURRENT_TIMESTAMP, p_cliente_id)
    RETURNING id INTO v_venta_id;

    INSERT INTO ventas_detalle(venta_id, producto_id, cantidad, precio_unitario)
    VALUES (v_venta_id, p_producto_id, p_cantidad, v_precio_unitario);


    UPDATE productos
    SET stock = stock - p_cantidad
    WHERE id = p_producto_id;

    RAISE NOTICE 'Venta registrada exitosamente. venta_id=%', v_venta_id;
    
END;
$$ LANGUAGE plpgsql;


SELECT registrar_ventas(1, 2, 5);

SELECT registrar_ventas(1, 2, 50);

SELECT registrar_ventas(999, 2, 1);

SELECT registrar_ventas(1, 999, 1);


#TRIGGERS
-- 1
CREATE OR REPLACE FUNCTION fn_actualizar_stock()
RETURNS TRIGGER AS $$
DECLARE
    stock_actual INT;
BEGIN
    SELECT stock INTO stock_actual
    FROM productos
    WHERE id = NEW.producto_id;

    IF stock_actual IS NULL THEN
        RAISE EXCEPTION 'El producto con id % no existe.', NEW.producto_id;
    END IF;

    IF stock_actual < NEW.cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente para el producto % (stock disponible: %, solicitado: %).',
            NEW.producto_id, stock_actual, NEW.cantidad;
    END IF;

    UPDATE productos
    SET stock = stock - NEW.cantidad
    WHERE id = NEW.producto_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_actualizar_stock
BEFORE INSERT ON ventas_detalle
FOR EACH ROW
EXECUTE FUNCTION fn_actualizar_stock();

-- 2
CREATE OR REPLACE FUNCTION fn_auditoria_ventas()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO auditoria_ventas (venta_id, usuario)
    VALUES (NEW.id, current_user);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auditoria_ventas
AFTER INSERT ON ventas
FOR EACH ROW
EXECUTE FUNCTION fn_auditoria_ventas();

--3

CREATE OR REPLACE FUNCTION fn_alerta_stock()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.stock = 0 AND OLD.stock <> 0 THEN
        INSERT INTO alertas_stock (producto_id, nombre_producto, mensaje)
        VALUES (NEW.id, NEW.nombre, 'El producto se ha agotado');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_alerta_stock
AFTER UPDATE OF stock ON productos
FOR EACH ROW
EXECUTE FUNCTION fn_alerta_stock();

--4

CREATE OR REPLACE FUNCTION fn_validar_cliente()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.correo IS NULL OR NEW.correo = '' THEN
        RAISE EXCEPTION 'El correo no puede estar vacío';
    END IF;

    IF EXISTS (SELECT 1 FROM clientes WHERE correo = NEW.correo) THEN
        RAISE EXCEPTION 'Ya existe un cliente con el correo %', NEW.correo;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_cliente
BEFORE INSERT ON clientes
FOR EACH ROW
EXECUTE FUNCTION fn_validar_cliente();

--5

CREATE OR REPLACE FUNCTION fn_historial_precios()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.precio <> OLD.precio THEN
        INSERT INTO historial_precios (producto_id, precio_anterior, precio_nuevo)
        VALUES (OLD.id, OLD.precio, NEW.precio);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_historial_precios
AFTER UPDATE OF precio ON productos
FOR EACH ROW
EXECUTE FUNCTION fn_historial_precios();

--6

CREATE OR REPLACE FUNCTION fn_bloqueo_proveedor()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM productos WHERE proveedor_id = OLD.id) THEN
        RAISE EXCEPTION 'No se puede eliminar el proveedor %, tiene productos asociados.', OLD.id;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bloqueo_proveedor
BEFORE DELETE ON proveedores
FOR EACH ROW
EXECUTE FUNCTION fn_bloqueo_proveedor();

--7

CREATE OR REPLACE FUNCTION fn_control_fecha_venta()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.fecha > NOW() THEN
        RAISE EXCEPTION 'La fecha de la venta no puede ser futura (%).', NEW.fecha;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_control_fecha_venta
BEFORE INSERT ON ventas
FOR EACH ROW
EXECUTE FUNCTION fn_control_fecha_venta();

--8
CREATE OR REPLACE FUNCTION fn_activar_cliente()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT cliente_id
        FROM ventas
        WHERE cliente_id = NEW.cliente_id
          AND fecha >= NOW() - INTERVAL '6 months'
    ) THEN
        UPDATE clientes
        SET estado = 'activo'
        WHERE id = NEW.cliente_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_activar_cliente
BEFORE INSERT ON ventas
FOR EACH ROW
EXECUTE FUNCTION fn_activar_cliente();



