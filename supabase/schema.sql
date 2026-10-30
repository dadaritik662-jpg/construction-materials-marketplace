CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- CUSTOMER PROFILES
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL DEFAULT '',
    phone TEXT,
    role TEXT NOT NULL DEFAULT 'buyer'
        CHECK (role IN ('buyer','supplier','transporter','contractor','admin')),
    city TEXT,
    state TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- SUPPLIER BUSINESSES
CREATE TABLE public.suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    business_name TEXT NOT NULL,
    phone TEXT,
    address TEXT,
    city TEXT,
    state TEXT,
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- MATERIAL CATEGORIES
CREATE TABLE public.categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL
);

INSERT INTO public.categories (name) VALUES
('Sand'),
('Aggregate / Gitti'),
('Bricks'),
('Cement'),
('Steel'),
('Other')
ON CONFLICT (name) DO NOTHING;

-- MATERIAL LISTINGS
CREATE TABLE public.materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE CASCADE,
    category_id UUID REFERENCES public.categories(id),
    material_name TEXT NOT NULL,
    description TEXT,
    price NUMERIC(12,2),
    unit TEXT DEFAULT 'unit',
    stock_quantity NUMERIC(12,2) DEFAULT 0,
    city TEXT,
    available BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- BUYER REQUIREMENTS
CREATE TABLE public.requirements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    buyer_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    category_id UUID REFERENCES public.categories(id),
    material_name TEXT NOT NULL,
    quantity NUMERIC(12,2),
    unit TEXT,
    delivery_location TEXT,
    description TEXT,
    status TEXT DEFAULT 'open',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- SUPPLIER QUOTATIONS
CREATE TABLE public.quotations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requirement_id UUID REFERENCES public.requirements(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE CASCADE,
    quoted_price NUMERIC(12,2),
    delivery_charge NUMERIC(12,2) DEFAULT 0,
    message TEXT,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ORDERS
CREATE TABLE public.orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    buyer_id UUID REFERENCES auth.users(id),
    supplier_id UUID REFERENCES public.suppliers(id),
    material_id UUID REFERENCES public.materials(id),
    quantity NUMERIC(12,2) NOT NULL,
    total_amount NUMERIC(12,2),
    delivery_address TEXT,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- TRANSPORTERS
CREATE TABLE public.transporters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    business_name TEXT,
    vehicle_type TEXT,
    vehicle_number TEXT,
    capacity NUMERIC(12,2),
    phone TEXT,
    city TEXT,
    state TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- SECURITY
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.requirements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quotations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transporters ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile"
ON public.profiles FOR SELECT
TO authenticated
USING (auth.uid() = id);

CREATE POLICY "Users can create own profile"
ON public.profiles FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

CREATE POLICY "Public can view suppliers"
ON public.suppliers FOR SELECT
TO anon, authenticated
USING (true);

CREATE POLICY "Owners can manage suppliers"
ON public.suppliers FOR ALL
TO authenticated
USING (auth.uid() = owner_id)
WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Public can view categories"
ON public.categories FOR SELECT
TO anon, authenticated
USING (true);

CREATE POLICY "Public can view available materials"
ON public.materials FOR SELECT
TO anon, authenticated
USING (available = true);

CREATE POLICY "Suppliers can manage their materials"
ON public.materials FOR ALL
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.suppliers s
        WHERE s.id = supplier_id AND s.owner_id = auth.uid()
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.suppliers s
        WHERE s.id = supplier_id AND s.owner_id = auth.uid()
    )
);

CREATE POLICY "Buyers can manage own requirements"
ON public.requirements FOR ALL
TO authenticated
USING (auth.uid() = buyer_id)
WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "Users can view own orders"
ON public.orders FOR SELECT
TO authenticated
USING (
    auth.uid() = buyer_id OR
    EXISTS (
        SELECT 1 FROM public.suppliers s
        WHERE s.id = supplier_id AND s.owner_id = auth.uid()
    )
);

CREATE POLICY "Buyers can create own orders"
ON public.orders FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "Transporters can manage own profile"
ON public.transporters FOR ALL
TO authenticated
USING (auth.uid() = owner_id)
WITH CHECK (auth.uid() = owner_id);
