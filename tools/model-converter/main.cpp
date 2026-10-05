#include "ufbx.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <map>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
using D=ufbx_vec3;
D sub(D a,D b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
D cross(D a,D b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
double dot(D a,D b){return a.x*b.x+a.y*b.y+a.z*b.z;}
D normal(D v){double l=std::sqrt(dot(v,v));if(l<1e-10)throw std::runtime_error("zero normal");return {v.x/l,v.y/l,v.z/l};}
void bounds(D& lo,D& hi,D p){lo={std::min(lo.x,p.x),std::min(lo.y,p.y),std::min(lo.z,p.z)};hi={std::max(hi.x,p.x),std::max(hi.y,p.y),std::max(hi.z,p.z)};}
template<class T>void put(std::ofstream& f,T v){f.write(reinterpret_cast<char*>(&v),sizeof(v));}
void vec(std::ofstream& f,D v){put(f,float(v.x));put(f,float(v.y));put(f,float(v.z));}
struct Vertex{D p,n;ufbx_vec2 uv;};
struct Part{uint32_t role,texture;D pivot,lo{1e30,1e30,1e30},hi{-1e30,-1e30,-1e30};ufbx_vec2 uvlo{1e30,1e30},uvhi{-1e30,-1e30};D color;std::string name,material;std::vector<Vertex> corners;};
int main(int argc,char** argv)try {
    if(argc!=2 && argc!=3)return 2;
    ufbx_load_opts opts{};opts.target_axes=ufbx_axes_left_handed_y_up;opts.target_unit_meters=1;opts.generate_missing_normals=true;
    ufbx_error error{};auto scene=std::unique_ptr<ufbx_scene,decltype(&ufbx_free_scene)>(ufbx_load_file(argv[1],&opts,&error),ufbx_free_scene);
    if(!scene)throw std::runtime_error(error.description.data);
    D lo{1e30,1e30,1e30},hi{-1e30,-1e30,-1e30};
    const std::map<uint32_t,uint32_t> selected{{2,0},{4,0},{5,3},{6,4},{10,1},{11,2}};
    for(auto node:scene->nodes){
        auto pos=ufbx_transform_position(&node->node_to_world,{});
        printf("%u %s pivot=(%.4f,%.4f,%.4f)",node->typed_id,node->name.data,pos.x,pos.y,pos.z);
        if(auto mesh=node->mesh){
            D nlo{1e30,1e30,1e30},nhi{-1e30,-1e30,-1e30};
            for(auto v:mesh->vertices){auto p=ufbx_transform_position(&node->geometry_to_world,v);bounds(nlo,nhi,p);if(selected.contains(node->typed_id))bounds(lo,hi,p);}
            printf(" tri=%zu bounds=(%.4f,%.4f,%.4f)-(%.4f,%.4f,%.4f)",mesh->num_triangles,nlo.x,nlo.y,nlo.z,nhi.x,nhi.y,nhi.z);
            for(auto mat:node->materials){auto m=mat->fbx.diffuse_color;printf(" material=%s rgb=(%.3f,%.3f,%.3f) tex=%s",mat->name.data,m.value_vec3.x,m.value_vec3.y,m.value_vec3.z,m.texture?m.texture->filename.data:"-");}
        }puts("");
    }
    if(argc==2)return 0;
    const double scale=2.2/(hi.z-lo.z);D origin{(hi.x+lo.x)/2,lo.y,(hi.z+lo.z)/2};
    origin.x=(ufbx_transform_position(&scene->nodes[10]->node_to_world,{}).x+ufbx_transform_position(&scene->nodes[11]->node_to_world,{}).x)/2;
    auto convert=[&](D p){return D{(p.x-origin.x)*scale,(p.y-origin.y)*scale,(p.z-origin.z)*scale};};
    std::vector<Part> parts;
    for(auto node:scene->nodes){
        if(!selected.contains(node->typed_id))continue;
        auto mesh=node->mesh;auto nm=ufbx_matrix_for_normals(&node->geometry_to_world);
        for(auto group:mesh->material_parts){
            if(!group.num_triangles)continue;
            auto mat=node->materials[group.index];auto diffuse=mat->fbx.diffuse_color;
            Part part{};part.role=selected.at(node->typed_id);part.texture=diffuse.texture?1:0;part.color=diffuse.has_value?diffuse.value_vec3:D{1,1,1};
            part.pivot=convert(ufbx_transform_position(&node->node_to_world,{}));part.name=node->name.data;part.material=mat->name.data;
            for(auto faceId:group.face_indices){
                auto face=mesh->faces[faceId];std::vector<uint32_t> tris((face.num_indices-2)*3);
                const auto num=ufbx_triangulate_face(tris.data(),tris.size(),mesh,face);
                for(size_t t=0;t<num;t++){
                    std::array<Vertex,3> vs;
                    for(int j=0;j<3;j++){auto ix=tris[t*3+j];vs[j]={sub(convert(ufbx_transform_position(&node->geometry_to_world,ufbx_get_vertex_vec3(&mesh->vertex_position,ix))),part.pivot),normal(ufbx_transform_direction(&nm,ufbx_get_vertex_vec3(&mesh->vertex_normal,ix))),ufbx_get_vertex_vec2(&mesh->vertex_uv,ix)};}
                    // Unity winding: outward supplied normal and cross must agree, including mirrored instances.
                    if(dot(cross(sub(vs[1].p,vs[0].p),sub(vs[2].p,vs[0].p)),vs[0].n)<0)std::swap(vs[1],vs[2]);
                    for(auto v:vs){bounds(part.lo,part.hi,v.p);part.uvlo={std::min(part.uvlo.x,v.uv.x),std::min(part.uvlo.y,v.uv.y)};part.uvhi={std::max(part.uvhi.x,v.uv.x),std::max(part.uvhi.y,v.uv.y)};part.corners.push_back(v);}
                }
            }
            parts.push_back(std::move(part));
        }
    }
    if(parts.empty()||parts.size()>32)throw std::runtime_error("part count");
    std::ofstream out(argv[2],std::ios::binary);if(!out)throw std::runtime_error("output");out.write("ZMLBIKE1",8);put(out,uint32_t(parts.size()));
    std::ofstream report(std::string(argv[2])+".txt");size_t totalV=0,totalT=0;
    for(auto& p:parts){
        D center{(p.hi.x+p.lo.x)/2,(p.hi.y+p.lo.y)/2,(p.hi.z+p.lo.z)/2};D extent{std::max((p.hi.x-p.lo.x)/2,1e-6),std::max((p.hi.y-p.lo.y)/2,1e-6),std::max((p.hi.z-p.lo.z)/2,1e-6)};
        ufbx_vec2 uvextent{std::max(p.uvhi.x-p.uvlo.x,1e-6),std::max(p.uvhi.y-p.uvlo.y,1e-6)};
        std::map<std::array<uint16_t,6>,uint16_t> lookup;std::vector<std::array<uint16_t,6>> vertices;std::vector<uint16_t> indices;
        auto sn=[](double x){return uint16_t(int16_t(std::lround(std::clamp(x,-1.0,1.0)*32767)));};auto un=[](double x){return uint16_t(std::lround(std::clamp(x,0.0,1.0)*65535));};
        for(auto v:p.corners){
            double divisor=std::abs(v.n.x)+std::abs(v.n.y)+std::abs(v.n.z);
            double nx=v.n.x/divisor,ny=v.n.y/divisor;
            if(v.n.z<0){double ox=nx;nx=(1-std::abs(ny))*(ox>=0?1:-1);ny=(1-std::abs(ox))*(ny>=0?1:-1);}
            auto oct=[](double n){return uint8_t(std::lround((std::clamp(n,-1.0,1.0)*.5+.5)*255));};
            std::array<uint16_t,6> packed{sn((v.p.x-center.x)/extent.x),sn((v.p.y-center.y)/extent.y),sn((v.p.z-center.z)/extent.z),uint16_t(oct(nx)|(uint16_t(oct(ny))<<8)),un((v.uv.x-p.uvlo.x)/uvextent.x),un((v.uv.y-p.uvlo.y)/uvextent.y)};
            auto found=lookup.find(packed);if(found==lookup.end()){if(vertices.size()>=65535)throw std::runtime_error("part too large");auto id=uint16_t(vertices.size());lookup.emplace(packed,id);vertices.push_back(packed);indices.push_back(id);}else indices.push_back(found->second);
        }
        put(out,p.role);put(out,uint32_t(vertices.size()));put(out,uint32_t(indices.size()));put(out,p.texture);vec(out,p.pivot);vec(out,center);vec(out,extent);
        put(out,float(p.uvlo.x));put(out,float(p.uvlo.y));put(out,float(uvextent.x));put(out,float(uvextent.y));vec(out,p.color);put(out,1.f);
        for(auto v:vertices)for(auto x:v)put(out,x);for(auto ix:indices)put(out,ix);
        totalV+=vertices.size();totalT+=indices.size()/3;
        report<<p.name<<" / "<<p.material<<" role="<<p.role<<" textured="<<p.texture<<" vertices="<<vertices.size()<<" triangles="<<indices.size()/3<<" pivot="<<p.pivot.x<<","<<p.pivot.y<<","<<p.pivot.z<<"\n";
    }
    report<<"total vertices="<<totalV<<" triangles="<<totalT<<" dimensions="<<(hi.x-lo.x)*scale<<","<<(hi.y-lo.y)*scale<<",2.2\n";
    if(!out)throw std::runtime_error("write output");printf("Exported %zu parts, %zu vertices, %zu triangles\n",parts.size(),totalV,totalT);
    return 0;
}catch(const std::exception& e){fprintf(stderr,"%s\n",e.what());return 1;}
